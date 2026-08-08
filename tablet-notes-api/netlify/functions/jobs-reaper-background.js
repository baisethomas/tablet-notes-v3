const { randomUUID } = require('crypto');
const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { withLogging } = require('./utils/logger');
const { withTimeout } = require('./utils/security');
const {
  JOB_KINDS,
  JOB_STATUS,
  ACTIVE_STATUSES,
  isStale,
  planFailure,
  webhookUrlFor,
  classifySubmitFailure,
  handoffGraceExpired,
  matchProviderTranscript,
  scanReachedCutoff,
  HANDOFF_ABANDON_MS
} = require('./utils/processingJobs');
const { completeTranscriptionJob } = require('./utils/completeTranscription');
const { claimJob, releaseClaim, markUncertainHandoff } = require('./utils/jobClaim');

/**
 * Scheduled reaper for processing_jobs (TAB-72).
 *
 * Webhooks are best-effort: they get dropped, the provider stalls, or our
 * submit call failed after the row was written. This sweep is the safety net
 * that makes "no job is ever silently lost" true rather than aspirational:
 *
 *   1. queued transcription jobs whose backoff elapsed  -> (re)submit to AssemblyAI
 *   2. submitted/running jobs past the stale window     -> reconcile against the
 *      provider's actual state, completing or failing them
 *   3. queued summary jobs                              -> generate and persist
 *
 * A `-background` function (15-minute budget) rather than a plain scheduled one:
 * summary generation alone can take ~55s and a sweep may handle several jobs.
 * Schedule is configured in netlify.toml.
 */

const BATCH_LIMIT = 20;

function supabaseClient() {
  return createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
}

async function resubmitTranscription({ supabase, assembly, job, logger }) {
  if (!job.audio_file_path) {
    const failure = planFailure(job, 'no audio_file_path recorded; cannot resubmit');
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    return;
  }

  // Claim BEFORE spending money (PR #37 review round 2). Two overlapping
  // sweeps — or a sweep racing POST /api/jobs — could otherwise both submit
  // this row to AssemblyAI, billing twice and leaving one provider job
  // unreconcilable when the second id overwrote the first.
  const claimed = await claimJob({ supabase, jobId: job.id });
  if (!claimed) {
    logger.info('Reaper skipping job claimed by another worker', { jobId: job.id });
    return;
  }

  const { data: signed, error: signedError } = await supabase
    .storage.from('sermon-audio')
    .createSignedUrl(job.audio_file_path, 7200);

  if (signedError || !signed?.signedUrl) {
    await releaseClaim({
      supabase,
      jobId: job.id,
      error: `signed url failed: ${signedError?.message || 'unknown'}`
    });
    return;
  }

  const webhookUrl = webhookUrlFor(
    process.env.PUBLIC_API_BASE_URL || 'https://comfy-daffodil-7ecc55.netlify.app',
    job.id
  );

  try {
    const transcript = await assembly.transcripts.submit({
      audio: signed.signedUrl,
      speaker_labels: true,
      auto_chapters: false,
      filter_profanity: false,
      format_text: true,
      webhook_url: webhookUrl,
      webhook_auth_header_name: 'x-tabletnotes-webhook-secret',
      webhook_auth_header_value: process.env.ASSEMBLYAI_WEBHOOK_SECRET
    });

    // Already claimed as 'submitted'; record the provider id and attempt count.
    const { error: recordError } = await supabase
      .from('processing_jobs')
      .update({
        provider_job_id: transcript.id,
        attempts: (job.attempts || 0) + 1,
        last_error: null,
        next_attempt_at: null
      })
      .eq('id', job.id);

    if (recordError) {
      // Same rule as jobs.js: the audio is already at the provider, so this
      // failure must not re-queue anything. The callback carries our job id.
      logger.warn('Reaper could not record provider job id; job stays submitted', {
        jobId: job.id,
        providerJobId: transcript.id
      });
      return;
    }

    logger.info('Reaper resubmitted transcription', { jobId: job.id, providerJobId: transcript.id });
  } catch (error) {
    // Only re-queue a submission that provably never left this process. An
    // uncertain one stays 'submitted' — resubmitting it would bill twice and
    // orphan whichever provider job we then stopped tracking.
    if (classifySubmitFailure(error) !== 'not-sent') {
      await markUncertainHandoff({ supabase, jobId: job.id, error });
      logger.warn('Reaper submission outcome uncertain; leaving job submitted', { jobId: job.id });
      return;
    }

    const failure = planFailure(job, error);
    await supabase
      .from('processing_jobs')
      .update({ ...failure, submitted_at: null })
      .eq('id', job.id);
    logger.warn('Reaper resubmission failed', { jobId: job.id, status: failure.status });
  }
}

const LOOKUP_PAGE_SIZE = 100;
const LOOKUP_MAX_PAGES = 20;

/**
 * Ask AssemblyAI whether this job's audio was already submitted, for the case
 * where we lost the provider id (or never got one back).
 *
 * Returns `{ transcript, conclusive }`. The second half is the important half
 * (PR #37 review round 5): "not in the page I looked at" is not the same claim
 * as "not at the provider", and only the latter justifies spending money on a
 * resubmit. Callers must not re-queue on an inconclusive answer.
 *
 * Transcripts list newest-first, so the scan pages backwards with `before_id`
 * until it passes the moment this job was submitted — at which point absence is
 * proven — or until it runs out of pages, which is not proof.
 */
async function findExistingProviderJob({ assembly, job, logger }) {
  if (!job.audio_file_path) return { transcript: null, conclusive: true };

  const cutoff = job.submitted_at || job.created_at;
  let beforeId;
  let scanned = 0;

  try {
    for (let page = 0; page < LOOKUP_MAX_PAGES; page += 1) {
      const params = { limit: LOOKUP_PAGE_SIZE };
      if (beforeId) params.before_id = beforeId;

      const response = await assembly.transcripts.list(params);
      const transcripts = response?.transcripts || [];
      scanned += transcripts.length;

      const match = matchProviderTranscript(transcripts, job);
      if (match) return { transcript: match, conclusive: true };

      if (scanReachedCutoff(transcripts, cutoff)) {
        logger.info('Scanned back past this job’s submit time; audio is not at the provider', {
          jobId: job.id,
          scanned
        });
        return { transcript: null, conclusive: true };
      }

      beforeId = transcripts[transcripts.length - 1]?.id;
      if (!beforeId) return { transcript: null, conclusive: true };
    }

    logger.warn('Provider transcript scan hit its page limit without reaching the cutoff', {
      jobId: job.id,
      scanned
    });
    return { transcript: null, conclusive: false };
  } catch (error) {
    logger.warn('Could not list provider transcripts', { jobId: job.id, error: error.message });
    return { transcript: null, conclusive: false };
  }
}

async function reconcileStale({ supabase, assembly, job, logger }) {
  if (!job.provider_job_id) {
    // Submitted with no provider id: either the submit never landed, or it
    // landed and we failed to record the id. We cannot tell them apart from
    // here, so we wait rather than guess — the callback carries our job id and
    // will complete the row within minutes if the audio really is at the
    // provider. Only once the grace window has passed with no callback at all
    // do we accept that nothing was ever submitted and re-queue.
    if (!handoffGraceExpired(job)) {
      logger.info('Job has an unresolved provider handoff; waiting out the grace window', {
        jobId: job.id
      });
      return;
    }

    // Before spending money on a resubmit, ASK the provider whether this audio
    // is already there (PR #37 review round 4). Re-queuing on an expired grace
    // window alone is still a guess: a transcription that is genuinely running
    // but slow would be submitted a second time. The storage path is the join
    // key both sides share — signed-URL tokens differ per mint, the object path
    // does not.
    const { transcript: adopted, conclusive } = await findExistingProviderJob({
      assembly,
      job,
      logger
    });

    if (adopted) {
      logger.warn('Adopted an existing provider job instead of resubmitting', {
        jobId: job.id,
        providerJobId: adopted.id
      });
      await supabase
        .from('processing_jobs')
        .update({ provider_job_id: adopted.id })
        .eq('id', job.id);
      // Reconcile it now that we know who it is, rather than waiting a sweep.
      await reconcileStale({ supabase, assembly, job: { ...job, provider_job_id: adopted.id }, logger });
      return;
    }

    if (!conclusive) {
      // We could not prove absence, so we must not spend money on a resubmit.
      // Retry the lookup next sweep — but not forever: past the abandon bound,
      // give up visibly rather than stalling silently (PR #37 review round 5).
      if (handoffGraceExpired(job, { graceMs: HANDOFF_ABANDON_MS })) {
        logger.error('Abandoning a job whose provider handoff could never be resolved', {
          jobId: job.id
        });
        await supabase
          .from('processing_jobs')
          .update({
            status: JOB_STATUS.DEAD,
            last_error:
              'Could not determine whether this recording reached the transcription provider. Not retried automatically to avoid duplicate processing.',
            next_attempt_at: null,
            completed_at: new Date().toISOString()
          })
          .eq('id', job.id);
        return;
      }

      logger.warn('Provider lookup inconclusive; leaving the job submitted for a later sweep', {
        jobId: job.id
      });
      return;
    }

    logger.warn('Provider handoff grace expired and the audio is provably absent; re-queuing', {
      jobId: job.id
    });
    await supabase
      .from('processing_jobs')
      .update({ status: JOB_STATUS.QUEUED, submitted_at: null, next_attempt_at: null })
      .eq('id', job.id);
    return;
  }

  try {
    const transcript = await assembly.transcripts.get(job.provider_job_id);

    if (transcript.status === 'completed') {
      // The webhook was lost. Run the SAME completion path the webhook runs —
      // transcript persist, job done, and summary chaining — rather than a
      // parallel copy that can drift (PR #37 review: this path was silently
      // skipping the summary job, so recovered sermons never got summarized).
      const result = await completeTranscriptionJob({ supabase, job, transcript, logger });
      if (result.ok) {
        logger.info('Reaper recovered a lost webhook completion', {
          jobId: job.id,
          summaryChained: result.summaryChained
        });
      }
      return;
    }

    if (transcript.status === 'error') {
      const failure = planFailure(job, transcript.error || 'provider error');
      await supabase.from('processing_jobs').update(failure).eq('id', job.id);
      return;
    }

    // Still genuinely processing: extend the window, don't touch attempts.
    await supabase
      .from('processing_jobs')
      .update({ status: JOB_STATUS.RUNNING, updated_at: new Date().toISOString() })
      .eq('id', job.id);
  } catch (error) {
    logger.warn('Reaper reconciliation failed', { jobId: job.id, error: error.message });
  }
}

/**
 * Mark a summary job complete. Returns the Supabase error, or null.
 *
 * Shared by both completion paths (generated-now and already-present) so the
 * "is it actually marked?" check cannot exist in one and be missing from the
 * other — the divergence this PR's review keeps finding.
 */
async function markSummaryJobDone({ supabase, jobId }) {
  const { error } = await supabase
    .from('processing_jobs')
    .update({
      status: JOB_STATUS.DONE,
      completed_at: new Date().toISOString(),
      last_error: null,
      next_attempt_at: null
    })
    .eq('id', jobId);

  return error || null;
}

async function runSummary({ supabase, job, logger }) {
  // Same claim discipline as transcription: OpenAI calls cost money, and two
  // overlapping sweeps must not both generate a summary for one job.
  const claimed = await claimJob({ supabase, jobId: job.id, toStatus: JOB_STATUS.RUNNING });
  if (!claimed) {
    logger.info('Reaper skipping summary job claimed by another worker', { jobId: job.id });
    return;
  }

  // If the summary already exists, the only thing left to do is mark the job.
  // This is what makes a retry after a failed completion-update free rather than
  // a second paid OpenAI call for output already sitting in the database.
  const { data: priorSummary } = await supabase
    .from('summaries')
    .select('text')
    .eq('sermon_id', job.sermon_id)
    .maybeSingle();

  if (priorSummary?.text?.trim()) {
    const completionError = await markSummaryJobDone({ supabase, jobId: job.id });
    if (completionError) {
      logger.warn('Summary already exists but the job could not be marked done', {
        jobId: job.id,
        error: completionError.message
      });
      const failure = planFailure(job, `completion update failed: ${completionError.message}`);
      await supabase.from('processing_jobs').update(failure).eq('id', job.id);
      return;
    }
    logger.info('Summary already present; marked job done without regenerating', { jobId: job.id });
    return;
  }

  const { data: transcript } = await supabase
    .from('transcripts')
    .select('text')
    .eq('sermon_id', job.sermon_id)
    .maybeSingle();

  const text = transcript?.text || '';
  if (text.trim().length < 50) {
    const failure = planFailure(job, 'transcript too short to summarize');
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    return;
  }

  const { data: sermon } = await supabase
    .from('sermons')
    .select('service_type')
    .eq('id', job.sermon_id)
    .maybeSingle();

  try {
    // Reuses the real /api/summarize endpoint over its internal service path
    // (shared secret + explicit acting user). PR #37 review correctly caught
    // that the endpoint this used to call, /api/summarize-internal, did not
    // exist — every summary job would have retried into 'dead'. Calling the
    // live endpoint also keeps exactly one copy of the summarization prompt.
    const response = await withTimeout(
      () => fetch(`${process.env.PUBLIC_API_BASE_URL || 'https://comfy-daffodil-7ecc55.netlify.app'}/api/summarize`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-tabletnotes-internal-secret': process.env.ASSEMBLYAI_WEBHOOK_SECRET || ''
        },
        body: JSON.stringify({
          text,
          serviceType: sermon?.service_type || 'Sermon',
          userId: job.user_id
        })
      }),
      120000
    )();

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`summarize returned ${response.status}: ${body.slice(0, 200)}`);
    }

    const payload = await response.json();
    const title = payload?.data?.title || null;
    const summaryText = payload?.data?.summary || '';

    if (!summaryText.trim()) {
      throw new Error('summarize returned an empty summary');
    }

    // Persist BEFORE marking done, same rule as transcript completion: a client
    // reacting to 'done' must never find a missing summary.
    const { data: existingSummary } = await supabase
      .from('summaries')
      .select('local_id')
      .eq('sermon_id', job.sermon_id)
      .maybeSingle();

    const { error: summaryError } = await supabase.from('summaries').upsert(
      {
        local_id: existingSummary?.local_id || randomUUID(),
        sermon_id: job.sermon_id,
        user_id: job.user_id,
        text: summaryText,
        status: 'complete',
        updated_at: new Date().toISOString()
      },
      { onConflict: 'sermon_id' }
    );

    if (summaryError) {
      throw new Error(`summary persist failed: ${summaryError.message}`);
    }

    // The generated title is worth keeping on the sermon, mirroring what the
    // client's SummaryRetryService does with it today.
    if (title) {
      await supabase
        .from('sermons')
        .update({ title, updated_at: new Date().toISOString() })
        .eq('id', job.sermon_id);
    }

    const completionError = await markSummaryJobDone({ supabase, jobId: job.id });
    if (completionError) {
      // The summary exists but the job still says 'running', which no sweep
      // reclaims. Throw so planFailure re-queues it; the retry is cheap because
      // runSummary short-circuits when the summary is already there.
      throw new Error(`summary completion update failed: ${completionError.message}`);
    }

    logger.info('Reaper completed summary job', { jobId: job.id, hasTitle: !!title });
  } catch (error) {
    const failure = planFailure(job, error);
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    logger.warn('Reaper summary failed', { jobId: job.id, status: failure.status });
  }
}

exports.handler = withLogging('jobs-reaper', async () => {
  const logger = { info: console.log, warn: console.warn, error: console.error };

  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    console.error('[jobs-reaper] Supabase not configured');
    return { statusCode: 500, body: 'not configured' };
  }

  const supabase = supabaseClient();
  const assembly = new AssemblyAI({ apiKey: process.env.ASSEMBLYAI_API_KEY });
  const nowIso = new Date().toISOString();

  const { data: jobs, error } = await supabase
    .from('processing_jobs')
    .select('*')
    .in('status', ACTIVE_STATUSES)
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${nowIso}`)
    .order('created_at', { ascending: true })
    .limit(BATCH_LIMIT);

  if (error) {
    console.error('[jobs-reaper] Failed to fetch jobs', error);
    return { statusCode: 500, body: 'fetch failed' };
  }

  let handled = 0;
  for (const job of jobs || []) {
    if (job.kind === JOB_KINDS.SUMMARY && job.status === JOB_STATUS.QUEUED) {
      await runSummary({ supabase, job, logger });
      handled += 1;
    } else if (job.kind === JOB_KINDS.TRANSCRIPTION && job.status === JOB_STATUS.QUEUED) {
      await resubmitTranscription({ supabase, assembly, job, logger });
      handled += 1;
    } else if (isStale(job)) {
      await reconcileStale({ supabase, assembly, job, logger });
      handled += 1;
    }
  }

  console.log(`[jobs-reaper] Swept ${jobs?.length || 0} candidate job(s), acted on ${handled}`);
  return { statusCode: 200, body: JSON.stringify({ candidates: jobs?.length || 0, handled }) };
});

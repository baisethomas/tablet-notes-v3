const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { withLogging } = require('./utils/logger');
const { withTimeout } = require('./utils/security');
const {
  JOB_KINDS,
  JOB_STATUS,
  ACTIVE_STATUSES,
  isStale,
  planFailure
} = require('./utils/processingJobs');

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

  const { data: signed, error: signedError } = await supabase
    .storage.from('sermon-audio')
    .createSignedUrl(job.audio_file_path, 7200);

  if (signedError || !signed?.signedUrl) {
    const failure = planFailure(job, `signed url failed: ${signedError?.message || 'unknown'}`);
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    return;
  }

  const webhookUrl = `${process.env.PUBLIC_API_BASE_URL || 'https://comfy-daffodil-7ecc55.netlify.app'}/api/assemblyai-webhook`;

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

    await supabase
      .from('processing_jobs')
      .update({
        status: JOB_STATUS.SUBMITTED,
        provider_job_id: transcript.id,
        submitted_at: new Date().toISOString(),
        attempts: (job.attempts || 0) + 1,
        last_error: null,
        next_attempt_at: null
      })
      .eq('id', job.id);

    logger.info('Reaper resubmitted transcription', { jobId: job.id, providerJobId: transcript.id });
  } catch (error) {
    const failure = planFailure(job, error);
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    logger.warn('Reaper resubmission failed', { jobId: job.id, status: failure.status });
  }
}

async function reconcileStale({ supabase, assembly, job, logger }) {
  if (!job.provider_job_id) {
    // Submitted-but-no-provider-id shouldn't happen; treat as resubmittable.
    await supabase
      .from('processing_jobs')
      .update({ status: JOB_STATUS.QUEUED, next_attempt_at: null })
      .eq('id', job.id);
    return;
  }

  try {
    const transcript = await assembly.transcripts.get(job.provider_job_id);

    if (transcript.status === 'completed') {
      // The webhook was lost. Persist exactly what the webhook would have.
      const text = transcript.text || '';
      const segments = Array.isArray(transcript.words) ? transcript.words : [];

      const { error: transcriptError } = await supabase.from('transcripts').upsert(
        {
          sermon_id: job.sermon_id,
          user_id: job.user_id,
          text,
          segments: segments.length > 0 ? segments : null,
          updated_at: new Date().toISOString()
        },
        { onConflict: 'sermon_id' }
      );

      if (transcriptError) {
        const failure = planFailure(job, `transcript persist failed: ${transcriptError.message}`);
        await supabase.from('processing_jobs').update(failure).eq('id', job.id);
        return;
      }

      await supabase
        .from('processing_jobs')
        .update({
          status: JOB_STATUS.DONE,
          completed_at: new Date().toISOString(),
          last_error: null,
          next_attempt_at: null
        })
        .eq('id', job.id);

      logger.info('Reaper recovered a lost webhook completion', { jobId: job.id });
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

async function runSummary({ supabase, job, logger }) {
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
    const response = await withTimeout(
      () => fetch(`${process.env.PUBLIC_API_BASE_URL || 'https://comfy-daffodil-7ecc55.netlify.app'}/api/summarize-internal`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-tabletnotes-webhook-secret': process.env.ASSEMBLYAI_WEBHOOK_SECRET || ''
        },
        body: JSON.stringify({
          text,
          serviceType: sermon?.service_type || 'Sermon',
          userId: job.user_id,
          sermonId: job.sermon_id
        })
      }),
      120000
    )();

    if (!response.ok) {
      throw new Error(`summarize-internal returned ${response.status}`);
    }

    await supabase
      .from('processing_jobs')
      .update({
        status: JOB_STATUS.DONE,
        completed_at: new Date().toISOString(),
        last_error: null,
        next_attempt_at: null
      })
      .eq('id', job.id);

    logger.info('Reaper completed summary job', { jobId: job.id });
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

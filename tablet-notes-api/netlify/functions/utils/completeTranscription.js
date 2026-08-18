const { randomUUID } = require('crypto');
const {
  JOB_KINDS,
  JOB_STATUS,
  idempotencyKey,
  planFailure,
  persistJobFailure,
  shouldChainSummary
} = require('./processingJobs');
const { applySermonStageTerminal, STATUS_NO_SPEECH, STATUS_COMPLETE } = require('./sermonStatus');

/**
 * The single implementation of "a transcription finished successfully".
 *
 * Two callers reach this state: the AssemblyAI webhook (the normal path) and
 * the reaper (when a webhook was lost and it discovers the provider already
 * finished). PR #37 review caught these having drifted — the reaper persisted
 * the transcript and marked the job done but forgot to chain the summary job,
 * so a recovered transcript silently never got summarized. Anything that must
 * happen on completion belongs HERE, once, so the two paths cannot diverge
 * again.
 *
 * Ordering is load-bearing: the transcript row is written and confirmed BEFORE
 * the job is marked done. A client reacting to `done` over Realtime must never
 * find a missing transcript (CLAUDE.md §9 #2 — never acknowledge ahead of the
 * write).
 *
 * @returns {Promise<{ok: true, summaryChained: boolean} | {ok: false, error: string}>}
 */
async function completeTranscriptionJob({ supabase, job, transcript, logger }) {
  const text = transcript?.text || '';
  const words = Array.isArray(transcript?.words) ? transcript.words : [];

  // transcripts.local_id is NOT NULL (it is the client's own transcript UUID).
  // On a first transcription there is no row yet, so this upsert becomes an
  // INSERT and omitting local_id fails the whole write — which would leave the
  // job retrying forever against a constraint it can never satisfy. Reuse the
  // existing row's local_id when there is one so the client's identifier is
  // preserved across re-transcription; mint one only when creating.
  const { data: existingTranscript } = await supabase
    .from('transcripts')
    .select('local_id')
    .eq('sermon_id', job.sermon_id)
    .maybeSingle();

  const localId = existingTranscript?.local_id || randomUUID();

  const { error: transcriptError } = await supabase.from('transcripts').upsert(
    {
      local_id: localId,
      sermon_id: job.sermon_id,
      user_id: job.user_id,
      text,
      segments: words.length > 0 ? words : null,
      status: 'complete',
      updated_at: new Date().toISOString()
    },
    { onConflict: 'sermon_id' }
  );

  if (transcriptError) {
    // Do NOT mark the job done — leave it retryable so the transcript isn't lost.
    const failure = planFailure(job, `transcript persist failed: ${transcriptError.message}`);
    await persistJobFailure({ supabase, job, failure, logger });
    logger?.error?.('Failed to persist transcript', { jobId: job.id }, transcriptError);
    return { ok: false, error: transcriptError.message };
  }

  // The provider can succeed and still return nothing: the recording contained
  // no speech. Five such sermons exist in production. `complete` would put a
  // completion badge over a transcript the user does not have, so this stops on
  // its own terminal state instead (TAB-85).
  const hasSpeech = text.trim().length > 0;

  // Before marking the job done, for the same reason the transcript is written
  // first: a client reacting to `done` over Realtime must not find the sermon
  // still claiming to be pending (TAB-89). Non-fatal — see applySermonStageTerminal.
  await applySermonStageTerminal({
    supabase,
    sermonId: job.sermon_id,
    stage: 'transcription',
    status: hasSpeech ? STATUS_COMPLETE : STATUS_NO_SPEECH,
    logger
  });

  // Nothing will ever chain a summary for an empty transcript, so leaving the
  // summary stage `pending` would spin forever — the same bug, one tab over.
  if (!hasSpeech) {
    await applySermonStageTerminal({
      supabase,
      sermonId: job.sermon_id,
      stage: 'summary',
      status: STATUS_NO_SPEECH,
      logger
    });
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

  // Chain the summary stage as its own durable job: a summary failure must
  // never cost the transcript, and the reaper drives it independently.
  let summaryChained = false;
  if (shouldChainSummary(job, text)) {
    const { error: chainError } = await supabase.from('processing_jobs').upsert(
      {
        user_id: job.user_id,
        sermon_id: job.sermon_id,
        sermon_local_id: job.sermon_local_id,
        kind: JOB_KINDS.SUMMARY,
        status: JOB_STATUS.QUEUED,
        idempotency_key: idempotencyKey(job.sermon_id, JOB_KINDS.SUMMARY),
        attempts: 0
      },
      { onConflict: 'idempotency_key', ignoreDuplicates: true }
    );

    if (chainError) {
      // The transcript is safe and the job is done; the summary just didn't get
      // queued. Log it loudly rather than failing the completion.
      logger?.error?.('Failed to chain summary job', { jobId: job.id }, chainError);
    } else {
      summaryChained = true;
    }
  }

  logger?.info?.('Transcription completed', {
    jobId: job.id,
    sermonId: job.sermon_id,
    textLength: text.length,
    segmentCount: words.length,
    summaryChained
  });

  return { ok: true, summaryChained };
}

module.exports = { completeTranscriptionJob };

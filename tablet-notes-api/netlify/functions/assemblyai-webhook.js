const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { withLogging } = require('./utils/logger');
const {
  withTimeout,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const {
  JOB_KINDS,
  JOB_STATUS,
  idempotencyKey,
  interpretWebhook,
  planFailure,
  secretMatches
} = require('./utils/processingJobs');

const WEBHOOK_SECRET_HEADER = 'x-tabletnotes-webhook-secret';

/**
 * POST /api/assemblyai-webhook — AssemblyAI completion callback (TAB-72).
 *
 * This is deliberately the ONLY function in the codebase without
 * createAuthMiddleware: the caller is AssemblyAI, not a signed-in user, so it
 * cannot present a Supabase JWT. Its proof is instead the shared secret we set
 * as webhook_auth_header_value at submit time (jobs.js) — checked here before
 * anything else happens. It is therefore NOT routed through withDefaults, whose
 * auth step would reject every legitimate call.
 *
 * Everything this handler writes is derived from the job row it looks up by
 * provider_job_id — never from the request body — so a forged callback that
 * somehow passed the secret check still cannot write another user's data.
 */
exports.handler = withLogging('assemblyai-webhook', async (event) => {
  const logger = event.logger;

  if (event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  const expectedSecret = process.env.ASSEMBLYAI_WEBHOOK_SECRET;
  if (!expectedSecret) {
    // Fail closed: an unconfigured secret must never mean "accept anything".
    logger.error('ASSEMBLYAI_WEBHOOK_SECRET not configured; rejecting callback');
    return createErrorResponse(new Error('Webhook not configured'), 503);
  }

  const providedSecret =
    event.headers[WEBHOOK_SECRET_HEADER] || event.headers[WEBHOOK_SECRET_HEADER.toUpperCase()];

  if (!secretMatches(providedSecret, expectedSecret)) {
    logger.security('webhook_auth_failed', { ip: event.headers['x-forwarded-for'] });
    return createErrorResponse(new Error('Unauthorized'), 401);
  }

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch (_) {
    return createErrorResponse(new Error('Invalid JSON in request body'), 400);
  }

  const interpreted = interpretWebhook(body);
  if (!interpreted.valid) {
    // 200, not 4xx: an unrecognized-but-authenticated event should not make
    // AssemblyAI retry forever.
    logger.warn('Ignoring webhook event', { reason: interpreted.reason });
    return createSuccessResponse({ ignored: true, reason: interpreted.reason }, 200);
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !supabaseKey) {
    logger.error('Supabase configuration missing');
    return createErrorResponse(new Error('Server configuration error'), 500);
  }
  const supabase = createClient(supabaseUrl, supabaseKey);

  const { data: job, error: jobError } = await supabase
    .from('processing_jobs')
    .select('*')
    .eq('provider_job_id', interpreted.transcriptId)
    .maybeSingle();

  if (jobError) {
    logger.error('Failed to look up job for webhook', { transcriptId: interpreted.transcriptId }, jobError);
    return createErrorResponse(new Error('Job lookup failed'), 500);
  }
  if (!job) {
    // Unknown provider id: nothing to do, and retrying won't help.
    logger.warn('No processing job for transcript', { transcriptId: interpreted.transcriptId });
    return createSuccessResponse({ ignored: true, reason: 'unknown provider job' }, 200);
  }

  // Terminal already: AssemblyAI retries callbacks, so this must be idempotent.
  if (job.status === JOB_STATUS.DONE) {
    return createSuccessResponse({ ignored: true, reason: 'already complete' }, 200);
  }

  if (interpreted.outcome === 'error') {
    const failure = planFailure(job, interpreted.error);
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    logger.warn('Provider reported transcription error', {
      jobId: job.id,
      attempts: failure.attempts,
      status: failure.status
    });
    return createSuccessResponse({ handled: true, status: failure.status }, 200);
  }

  // Completed: fetch the transcript body and persist it.
  try {
    const assembly = new AssemblyAI({ apiKey: process.env.ASSEMBLYAI_API_KEY });
    const transcript = await withTimeout(
      () => assembly.transcripts.get(interpreted.transcriptId),
      25000
    )();

    const text = transcript.text || '';
    const segments = Array.isArray(transcript.words) ? transcript.words : [];

    // Write-then-mark: the transcript row must land before the job is marked
    // done, or a client reacting to 'done' could read a missing transcript
    // (CLAUDE.md §9 #2 — never acknowledge before the write is confirmed).
    const { error: transcriptError } = await supabase
      .from('transcripts')
      .upsert(
        {
          sermon_id: job.sermon_id,
          user_id: job.user_id,
          text,
          // Prod stores segments as JSON; null when the provider returned none.
          segments: segments.length > 0 ? segments : null,
          updated_at: new Date().toISOString()
        },
        { onConflict: 'sermon_id' }
      );

    if (transcriptError) {
      // Do NOT mark the job done — leave it retryable.
      const failure = planFailure(job, `transcript persist failed: ${transcriptError.message}`);
      await supabase.from('processing_jobs').update(failure).eq('id', job.id);
      logger.error('Failed to persist transcript', { jobId: job.id }, transcriptError);
      return createErrorResponse(new Error('Failed to persist transcript'), 500);
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

    // Chain the summary stage as its own durable job, so a summary failure
    // never costs the transcript and the reaper can drive it independently.
    if (job.kind === JOB_KINDS.TRANSCRIPTION && text.trim().length >= 50) {
      await supabase
        .from('processing_jobs')
        .upsert(
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
    }

    logger.info('Transcription completed via webhook', {
      jobId: job.id,
      sermonId: job.sermon_id,
      textLength: text.length,
      segmentCount: segments.length
    });

    return createSuccessResponse({ handled: true, status: JOB_STATUS.DONE }, 200);
  } catch (error) {
    const failure = planFailure(job, error);
    await supabase.from('processing_jobs').update(failure).eq('id', job.id);
    logger.error('Webhook completion handling failed', { jobId: job.id }, error);
    return createErrorResponse(new Error('Webhook handling failed'), 500);
  }
});

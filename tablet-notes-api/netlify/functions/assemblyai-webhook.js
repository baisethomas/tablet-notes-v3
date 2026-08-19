const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { withLogging } = require('./utils/logger');
const { Validator } = require('./utils/validator');
const {
  withTimeout,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const {
  JOB_STATUS,
  interpretWebhook,
  planFailure,
  persistJobFailure,
  secretMatches,
  jobIdFromWebhookQuery
} = require('./utils/processingJobs');
const { completeTranscriptionJob } = require('./utils/completeTranscription');

const WEBHOOK_SECRET_HEADER = 'x-tabletnotes-webhook-secret';
const MAX_ERROR_CHARS = 500;

/**
 * Ask the provider what actually went wrong (TAB-85).
 *
 * The error callback carries `status: "error"` and, in practice, no reason —
 * so the stored `last_error` was the same generic sentence for every failure.
 * In production that made 19 dead jobs indistinguishable and hid the real
 * cause (unplayable audio, TAB-86) behind a string that described nothing.
 *
 * Best-effort by design: this runs on a path that has already failed, so a
 * lookup that times out or throws must not change the outcome. The caller
 * falls back to the generic message.
 *
 * Bounded twice over. The 3s timeout is deliberately short: AssemblyAI retries
 * a callback it considers failed, so blocking the response on a slow lookup
 * would trade error detail for duplicate webhook deliveries. And the message is
 * truncated — `last_error` exists to be read in a ledger, not to store an
 * arbitrary-length provider payload.
 */
async function fetchProviderError(transcriptId, logger) {
  if (!transcriptId || !process.env.ASSEMBLYAI_API_KEY) return null;
  try {
    const assembly = new AssemblyAI({ apiKey: process.env.ASSEMBLYAI_API_KEY });
    const transcript = await withTimeout(() => assembly.transcripts.get(transcriptId), 3000)();
    const detail = typeof transcript?.error === 'string' ? transcript.error.trim() : '';
    return detail ? detail.slice(0, MAX_ERROR_CHARS) : null;
  } catch (error) {
    logger?.warn?.('Could not fetch provider error detail', { transcriptId, error: error.message });
    return null;
  }
}

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

  // Size cap before parsing. The endpoint is secret-gated rather than rate
  // limited (a per-user limiter has no user to key on, and throttling the
  // provider's callbacks would strand completed transcriptions), so bounding
  // the payload is the abuse control that actually applies here.
  const sizeValidation = Validator.validateRequestSize(event);
  if (!sizeValidation.valid) {
    return createErrorResponse(new Error(sizeValidation.error), 413);
  }

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch (_) {
    return createErrorResponse(new Error('Invalid JSON in request body'), 400);
  }

  // Structural validation of the only two fields we consume. Everything else
  // this handler writes is derived from the job row, never from this body.
  if (body.transcript_id !== undefined && typeof body.transcript_id !== 'string') {
    return createErrorResponse(new Error('transcript_id must be a string'), 400);
  }
  if (typeof body.transcript_id === 'string' && body.transcript_id.length > 100) {
    return createErrorResponse(new Error('transcript_id is too long'), 400);
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

  // Prefer OUR job id from the callback URL over the provider's id.
  //
  // Looking up only by provider_job_id assumes we managed to persist that id
  // after submitting — but that write can fail, and a submit can time out after
  // AssemblyAI already accepted the audio. In both cases the provider id lives
  // nowhere but AssemblyAI, and a paid, completed transcription would be thrown
  // away here as "unknown provider job" (PR #37 review round 3).
  const ownJobId = jobIdFromWebhookQuery(event.queryStringParameters);

  const lookup = ownJobId
    ? supabase.from('processing_jobs').select('*').eq('id', ownJobId)
    : supabase.from('processing_jobs').select('*').eq('provider_job_id', interpreted.transcriptId);

  const { data: job, error: jobError } = await lookup.maybeSingle();

  if (jobError) {
    logger.error('Failed to look up job for webhook', {
      transcriptId: interpreted.transcriptId,
      ownJobId
    }, jobError);
    return createErrorResponse(new Error('Job lookup failed'), 500);
  }
  if (!job) {
    // Neither id resolves: nothing to do, and retrying won't help.
    logger.warn('No processing job for callback', {
      transcriptId: interpreted.transcriptId,
      ownJobId
    });
    return createSuccessResponse({ ignored: true, reason: 'unknown job' }, 200);
  }

  // Heal the missing/mismatched provider id so the reaper can reconcile this
  // job later without depending on the callback arriving a second time.
  if (job.provider_job_id !== interpreted.transcriptId) {
    await supabase
      .from('processing_jobs')
      .update({ provider_job_id: interpreted.transcriptId })
      .eq('id', job.id);
    job.provider_job_id = interpreted.transcriptId;
  }

  // Terminal already: AssemblyAI retries callbacks, so this must be idempotent.
  if (job.status === JOB_STATUS.DONE) {
    return createSuccessResponse({ ignored: true, reason: 'already complete' }, 200);
  }

  if (interpreted.outcome === 'error') {
    // The callback body carries `status: "error"` but usually no reason, so
    // `interpretWebhook` falls back to the generic string. Storing that alone
    // is what made every failure look identical in the ledger: 19 jobs all
    // reading "AssemblyAI reported an error" hid the fact that the audio was
    // unplayable (TAB-86) and sent the first diagnosis down the wrong path.
    // One extra call on a path that has already failed is worth the detail.
    const detail = await fetchProviderError(interpreted.transcriptId, logger);

    const failure = planFailure(job, detail || interpreted.error);
    await persistJobFailure({ supabase, job, failure, logger });
    logger.warn('Provider reported transcription error', {
      jobId: job.id,
      attempts: failure.attempts,
      status: failure.status,
      providerError: failure.last_error
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

    // Single shared completion path — the reaper's lost-webhook recovery calls
    // the exact same function, so the two can't drift (they already had:
    // the reaper was silently skipping summary chaining).
    const result = await completeTranscriptionJob({ supabase, job, transcript, logger });

    if (!result.ok) {
      return createErrorResponse(new Error('Failed to persist transcript'), 500);
    }

    return createSuccessResponse(
      { handled: true, status: JOB_STATUS.DONE, summaryChained: result.summaryChained },
      200
    );
  } catch (error) {
    const failure = planFailure(job, error);
    await persistJobFailure({ supabase, job, failure, logger });
    logger.error('Webhook completion handling failed', { jobId: job.id }, error);
    return createErrorResponse(new Error('Webhook handling failed'), 500);
  }
});

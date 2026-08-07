const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { withDefaults } = require('./utils/withDefaults');
const {
  checkResourceOwnership,
  withTimeout,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const {
  JOB_KINDS,
  JOB_STATUS,
  idempotencyKey
} = require('./utils/processingJobs');
const { claimJob, releaseClaim } = require('./utils/jobClaim');

const assemblyAIBreaker = new CircuitBreaker(3, 60000);

/**
 * POST /api/jobs — create (or return) the durable processing job for a sermon
 * and submit it to AssemblyAI with a webhook (TAB-72).
 *
 * Replaces the fire-and-forget /api/transcribe + client-polling flow: the job
 * row is written to Postgres BEFORE the provider is called, so a job can never
 * be orphaned by the client dying. The response is 202 — the client is free to
 * be killed immediately after; completion arrives via the webhook -> Postgres
 * -> Realtime path.
 */
exports.handler = withDefaults(
  'jobs',
  { methods: ['POST'], rateLimit: 'transcription', auth: true, schema: 'processingJob' },
  async (event, context) => {
    const logger = event.logger;
    const user = event.user;
    const { sermonLocalId, filePath, kind = JOB_KINDS.TRANSCRIPTION } = event.validatedData;

    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !supabaseKey) {
      logger.error('Supabase configuration missing');
      return createErrorResponse(new Error('Server configuration error'), 500);
    }
    const webhookSecret = process.env.ASSEMBLYAI_WEBHOOK_SECRET;
    if (!webhookSecret) {
      // Fail closed: without the shared secret the webhook receiver cannot
      // authenticate callbacks, so a submitted job could never be completed.
      logger.error('ASSEMBLYAI_WEBHOOK_SECRET not configured');
      return createErrorResponse(new Error('Transcription service not available'), 503);
    }

    // The client only ever names its own storage path; enforce it the same way
    // transcribe.js does.
    if (!checkResourceOwnership(user, filePath)) {
      logger.security('unauthorized_file_access', {
        userId: user.id,
        filePath,
        ip: event.headers['x-forwarded-for']
      });
      return createErrorResponse(new Error('Access denied: You can only transcribe your own files'), 403);
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Resolve the server-side sermon row from the client's local id. The sermon
    // must already exist (create-sermon runs first in the client's save flow).
    const { data: sermon, error: sermonError } = await supabase
      .from('sermons')
      .select('id, user_id')
      .eq('user_id', user.id)
      .eq('local_id', sermonLocalId)
      .maybeSingle();

    if (sermonError) {
      logger.error('Failed to look up sermon', { userId: user.id, sermonLocalId }, sermonError);
      return createErrorResponse(new Error('Could not look up sermon'), 500);
    }
    if (!sermon) {
      return createErrorResponse(new Error('Sermon not found for this user'), 404);
    }

    const key = idempotencyKey(sermon.id, kind);

    // Idempotency: if a job already exists for this (sermon, kind), return it
    // rather than billing a second provider job. This is what makes the client
    // safe to retry after a lost response.
    const { data: existing } = await supabase
      .from('processing_jobs')
      .select('*')
      .eq('idempotency_key', key)
      .maybeSingle();

    if (existing && existing.status !== JOB_STATUS.DEAD && existing.status !== JOB_STATUS.FAILED) {
      logger.info('Returning existing processing job', {
        jobId: existing.id,
        status: existing.status,
        userId: user.id
      });
      return createSuccessResponse({ job: existing, reused: true }, 200, {
        ...(context.rateLimitHeaders || {}),
        origin: event.headers.origin
      });
    }

    // Write the durable row FIRST. If the provider submit below fails, the row
    // remains queued and the reaper drives it — the job is never lost.
    const jobPayload = {
      user_id: user.id,
      sermon_id: sermon.id,
      sermon_local_id: sermonLocalId,
      kind,
      status: JOB_STATUS.QUEUED,
      audio_file_path: filePath,
      idempotency_key: key,
      attempts: 0
    };

    const { data: job, error: insertError } = await supabase
      .from('processing_jobs')
      .upsert(jobPayload, { onConflict: 'idempotency_key' })
      .select()
      .single();

    if (insertError || !job) {
      logger.error('Failed to create processing job', { userId: user.id }, insertError);
      return createErrorResponse(new Error('Could not create processing job'), 500);
    }

    // Atomically CLAIM the job before spending money (PR #37 review). Shared
    // with the reaper's two submit paths so the three racing writers cannot
    // drift — round 2 of review found this claim present here but missing
    // there, which is exactly the divergence a shared helper prevents.
    const claimed = await claimJob({ supabase, jobId: job.id });

    if (!claimed) {
      // Someone else (a concurrent request, or the reaper) already claimed it.
      logger.info('Job already claimed by another submitter; returning existing', {
        jobId: job.id,
        userId: user.id
      });
      const { data: current } = await supabase
        .from('processing_jobs')
        .select('*')
        .eq('id', job.id)
        .single();
      return createSuccessResponse({ job: current || job, reused: true }, 200, {
        ...(context.rateLimitHeaders || {}),
        origin: event.headers.origin
      });
    }

    // Signed URL for the provider to pull the audio. 7200s matches the existing
    // transcribe.js budget; the reaper re-mints on resubmit.
    const { data: signedUrlData, error: signedUrlError } = await withTimeout(
      () => supabase.storage.from('sermon-audio').createSignedUrl(filePath, 7200),
      10000
    )();

    if (signedUrlError || !signedUrlData?.signedUrl) {
      logger.error('Signed URL creation failed', { filePath, userId: user.id }, signedUrlError);
      // Release the claim so the reaper (or a retry) can pick it up again —
      // leaving it 'submitted' with no provider id would strand the job until
      // the stale window elapsed.
      await releaseClaim({ supabase, jobId: job.id, error: 'signed url creation failed' });
      return createErrorResponse(new Error('Failed to access audio file in storage'), 500);
    }

    const assembly = new AssemblyAI({ apiKey: process.env.ASSEMBLYAI_API_KEY });
    const webhookUrl = `${process.env.PUBLIC_API_BASE_URL || 'https://comfy-daffodil-7ecc55.netlify.app'}/api/assemblyai-webhook`;

    try {
      const transcript = await withTimeout(
        () => assemblyAIBreaker.execute(() => assembly.transcripts.submit({
          audio: signedUrlData.signedUrl,
          speaker_labels: true,
          auto_chapters: false,
          filter_profanity: false,
          format_text: true,
          // The completion path. Without this the job would still need polling —
          // this single option is what removes the client from the loop.
          webhook_url: webhookUrl,
          webhook_auth_header_name: 'x-tabletnotes-webhook-secret',
          webhook_auth_header_value: webhookSecret
        })),
        20000
      )();

      // Already claimed as 'submitted' above; record the provider id.
      const { data: submitted } = await supabase
        .from('processing_jobs')
        .update({
          provider_job_id: transcript.id,
          last_error: null
        })
        .eq('id', job.id)
        .select()
        .single();

      logger.info('Processing job submitted', {
        jobId: job.id,
        providerJobId: transcript.id,
        userId: user.id
      });

      return createSuccessResponse({ job: submitted || job, reused: false }, 202, {
        ...(context.rateLimitHeaders || {}),
        origin: event.headers.origin
      });
    } catch (error) {
      // Release the claim and record the error; the reaper resubmits.
      await releaseClaim({ supabase, jobId: job.id, error });

      logger.error('Provider submission failed; job left queued for the reaper', {
        jobId: job.id,
        userId: user.id
      }, error);

      let statusCode = 502;
      if (error.message.includes('Circuit breaker')) statusCode = 503;
      else if (error.message.includes('timed out')) statusCode = 408;

      return createErrorResponse(
        new Error('Transcription could not be submitted yet; it has been queued and will retry automatically.'),
        statusCode
      );
    }
  }
);

const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { withDefaults } = require('./utils/withDefaults');
const { isOwnedObjectPath } = require('./utils/audioObjectPath');
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
  idempotencyKey,
  isExhaustedWithoutRetry,
  webhookUrlFor,
  classifySubmitFailure
} = require('./utils/processingJobs');
const { claimJob, releaseClaim, markUncertainHandoff } = require('./utils/jobClaim');
const { clearFailedPermanentStage } = require('./utils/sermonStatus');

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
    const {
      sermonLocalId,
      filePath: requestedFilePath,
      kind = JOB_KINDS.TRANSCRIPTION,
      retry = false
    } = event.validatedData;

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

    // A client-supplied path is only ever its own; enforce it the same way
    // transcribe.js does. A request with no path is the preferred shape — the
    // server then uses the sermon row's audio_file_path below, which it wrote
    // itself and so does not need to re-authorize.
    if (requestedFilePath && !checkResourceOwnership(user, requestedFilePath)) {
      logger.security('unauthorized_file_access', {
        userId: user.id,
        filePath: requestedFilePath,
        ip: event.headers['x-forwarded-for']
      });
      return createErrorResponse(new Error('Access denied: You can only transcribe your own files'), 403);
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Resolve the server-side sermon row from the client's local id. The sermon
    // must already exist (create-sermon runs first in the client's save flow).
    const { data: sermon, error: sermonError } = await supabase
      .from('sermons')
      .select('id, user_id, audio_file_path')
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

    // Prefer the server's own record of where the audio lives. The client only
    // knows this path in the one moment it uploads; a retry, a second device, or
    // a restore does not — so requiring it from the client would make the whole
    // pipeline un-retryable off the happy path.
    const filePath = requestedFilePath || sermon.audio_file_path;

    // Re-authorize even the stored path. The comment above used to say the
    // server "wrote it itself and so does not need to re-authorize" — that was
    // false: create-sermon persisted whatever the client sent. A sermon crafted
    // with a victim's path, then processed with no filePath in the request,
    // side-stepped the check above and had its audio signed with the SERVICE
    // ROLE key and sent to AssemblyAI (TAB-84). create-sermon now rejects such
    // paths, but rows written before that fix must not become exploitable, and
    // the two endpoints ship independently.
    if (filePath && !isOwnedObjectPath(filePath, user.id)) {
      logger.security('unauthorized_file_access', {
        userId: user.id,
        filePath: String(filePath).slice(0, 120),
        source: requestedFilePath ? 'request' : 'stored_sermon_row',
        ip: event.headers['x-forwarded-for']
      });
      return createErrorResponse(new Error('Access denied: You can only process your own files'), 403);
    }

    if (!filePath) {
      return createErrorResponse(
        new Error('Sermon has no uploaded audio yet; upload the recording before requesting processing.'),
        409
      );
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

    // Deliberately NOT an upsert-on-conflict (PR #37 review round 8). An upsert
    // writes status back to 'queued' over whatever is already there, so a second
    // concurrent request would reset a row the first request had just claimed —
    // both would then win the queued->submitted claim and both would pay for a
    // transcription. The claim cannot defend itself if its own precondition is
    // being rewritten underneath it.
    let job;

    // A `dead` job has already burned every attempt. Reviving it automatically
    // is what turned an unusable recording into an endless loop: the client's
    // sweep re-POSTs every pending/failed sermon on each launch, this branch
    // reset attempts to 0, and the reaper spent five more provider calls before
    // it died again — forever (TAB-85).
    //
    // So automatic dispatch no longer resurrects an exhausted job; it gets the
    // dead row back and leaves it alone. A deliberate retry still can, by
    // asking for it (`retry: true`). That path also clears `failed_permanent`
    // on the sermon — the only server-owned way out of the state TAB-85 wrote
    // (TAB-91). The revive update below resets `attempts` to 0 for that one
    // user-initiated budget; the automatic sweep still cannot revive, so
    // tapping Retry on dead audio cannot recreate the unbounded loop on its own.
    if (isExhaustedWithoutRetry(existing, retry)) {
      logger.info('Not reviving an exhausted job for an automatic dispatch', {
        jobId: existing.id,
        attempts: existing.attempts
      });
      return createSuccessResponse({ job: existing, reused: true, exhausted: true }, 200, {
        ...(context.rateLimitHeaders || {}),
        origin: event.headers.origin
      });
    }

    if (existing) {
      // Reached only for a dead/failed row (active ones returned above). Revive
      // it, but conditionally: `.in('status', [...])` means a row someone else
      // has already revived and claimed is left alone.
      const { data: revived } = await supabase
        .from('processing_jobs')
        .update({
          status: JOB_STATUS.QUEUED,
          audio_file_path: filePath,
          attempts: 0,
          last_error: null,
          next_attempt_at: null,
          provider_job_id: null,
          submitted_at: null,
          completed_at: null
        })
        .eq('id', existing.id)
        .in('status', [JOB_STATUS.DEAD, JOB_STATUS.FAILED])
        .select()
        .maybeSingle();

      if (!revived) {
        const { data: current } = await supabase
          .from('processing_jobs')
          .select('*')
          .eq('id', existing.id)
          .maybeSingle();
        logger.info('Job was revived by a concurrent request; returning it', { jobId: existing.id });
        return createSuccessResponse({ job: current || existing, reused: true }, 200, {
          ...(context.rateLimitHeaders || {}),
          origin: event.headers.origin
        });
      }
      job = revived;
    } else {
      const { data: inserted, error: insertError } = await supabase
        .from('processing_jobs')
        .insert(jobPayload)
        .select()
        .single();

      if (insertError) {
        // 23505 = unique violation on idempotency_key: a concurrent request got
        // there first. That is the constraint doing its job, not an error —
        // return their row rather than racing them for the provider.
        if (insertError.code === '23505') {
          const { data: current } = await supabase
            .from('processing_jobs')
            .select('*')
            .eq('idempotency_key', key)
            .maybeSingle();

          if (current) {
            logger.info('Lost the insert race; returning the concurrent job', { jobId: current.id });
            return createSuccessResponse({ job: current, reused: true }, 200, {
              ...(context.rateLimitHeaders || {}),
              origin: event.headers.origin
            });
          }
        }

        logger.error('Failed to create processing job', { userId: user.id }, insertError);
        return createErrorResponse(new Error('Could not create processing job'), 500);
      }
      job = inserted;
    }

    if (!job) {
      logger.error('Failed to create processing job', { userId: user.id });
      return createErrorResponse(new Error('Could not create processing job'), 500);
    }

    // Deliberate retry is the only way out of failed_permanent (TAB-91). Do this
    // after the job row is ready to run, and only when the caller asked — an
    // automatic sweep must never reopen a stopped stage.
    //
    // The clear must succeed before we claim/submit. If it fails and we still
    // bill AssemblyAI, TAB-90 will refuse the completion write while the stage
    // stays failed_permanent — a paid job whose result cannot land, plus a
    // false-success Retry on the client (Ternary blocking on #55).
    if (retry === true) {
      const cleared = await clearFailedPermanentStage({
        supabase,
        sermonId: sermon.id,
        stage: kind,
        logger
      });
      if (cleared.error) {
        // Revive (or insert) may already have left the row queued. Park it as
        // dead so the reaper cannot claim it while the stage is still closed.
        await supabase
          .from('processing_jobs')
          .update({
            status: JOB_STATUS.DEAD,
            last_error: 'failed to clear failed_permanent for retry'
          })
          .eq('id', job.id)
          .eq('status', JOB_STATUS.QUEUED);
        return createErrorResponse(
          new Error('Could not reopen this recording for retry. Please try again.'),
          500
        );
      }
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
    // Carries OUR job id, so completion never depends on us having successfully
    // written the provider's id back.
    const webhookUrl = webhookUrlFor(
      process.env.PUBLIC_API_BASE_URL || 'https://comfy-daffodil-7ecc55.netlify.app',
      job.id
    );

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

      // Already claimed as 'submitted' above; record the provider id. A failure
      // here is logged but NOT fatal and must not re-queue the job: the audio is
      // already at the provider, and the callback resolves by our job id.
      const { data: submitted, error: recordError } = await supabase
        .from('processing_jobs')
        .update({
          provider_job_id: transcript.id,
          last_error: null
        })
        .eq('id', job.id)
        .select()
        .single();

      if (recordError) {
        logger.error('Failed to record provider job id; job stays submitted', {
          jobId: job.id,
          providerJobId: transcript.id
        }, recordError);
      }

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
      // Only re-queue when the request provably never reached AssemblyAI. A
      // timeout is NOT proof of that: the submit may have been accepted and
      // answered slowly, in which case re-queuing bills a second transcription
      // and orphans the first. Uncertain handoffs stay 'submitted' and are
      // governed by the reaper's grace window instead.
      const classification = classifySubmitFailure(error);
      if (classification === 'not-sent') {
        await releaseClaim({ supabase, jobId: job.id, error });
      } else {
        await markUncertainHandoff({ supabase, jobId: job.id, error });
      }

      logger.error('Provider submission failed', {
        jobId: job.id,
        userId: user.id,
        classification,
        requeued: classification === 'not-sent'
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

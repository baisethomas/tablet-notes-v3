const { JOB_STATUS } = require('./processingJobs');

/**
 * Atomically claim a processing job before doing anything billable (TAB-72).
 *
 * The unique idempotency key prevents duplicate job *rows*; it does nothing to
 * prevent two workers from both calling AssemblyAI for the same row. Any code
 * path that submits to a provider must first win this claim.
 *
 * The serialization point is Postgres applying `eq('status', fromStatus)` as
 * part of the UPDATE: exactly one concurrent caller gets a row back, everyone
 * else gets null and must back off. There are three racing writers in this
 * system — POST /api/jobs, and two overlapping reaper sweeps — and PR #37
 * review found the claim missing from the reaper after it was added to the
 * endpoint. Sharing one implementation is what stops that from recurring.
 *
 * @returns {Promise<object|null>} the claimed row, or null if someone else won.
 */
async function claimJob({ supabase, jobId, fromStatus = JOB_STATUS.QUEUED, toStatus = JOB_STATUS.SUBMITTED, patch = {} }) {
  const { data } = await supabase
    .from('processing_jobs')
    .update({
      status: toStatus,
      submitted_at: new Date().toISOString(),
      ...patch
    })
    .eq('id', jobId)
    .eq('status', fromStatus)
    .select()
    .maybeSingle();

  return data || null;
}

/**
 * Release a claim so the job returns to the queue for a later attempt.
 * Used when the billable call never actually happened (signed-URL failure,
 * provider submit threw) — leaving the row 'submitted' with no provider id
 * would strand it until the stale window elapsed.
 */
async function releaseClaim({ supabase, jobId, error, retryDelayMs = 60_000 }) {
  await supabase
    .from('processing_jobs')
    .update({
      status: JOB_STATUS.QUEUED,
      submitted_at: null,
      last_error: typeof error === 'string' ? error : (error?.message || 'unknown error'),
      next_attempt_at: new Date(Date.now() + retryDelayMs).toISOString()
    })
    .eq('id', jobId);
}

/**
 * Record that a provider submit may or may not have landed (PR #37 review
 * round 3), WITHOUT returning the job to the queue.
 *
 * This is the counterpart to releaseClaim, and choosing between them is the
 * whole fix: releasing a claim whose provider call might have succeeded is what
 * causes a second billable submission plus an orphaned first transcription.
 * Here the row deliberately stays 'submitted' with its submitted_at intact, so
 * the reaper's grace window governs it. The callback still completes it — it
 * carries our job id, not just the provider's.
 *
 * Shared by both submit paths for the same reason claimJob is: round 2 of review
 * found a claim added in one place and missing in the other.
 */
async function markUncertainHandoff({ supabase, jobId, error }) {
  await supabase
    .from('processing_jobs')
    .update({
      last_error: `provider handoff uncertain: ${
        typeof error === 'string' ? error : (error?.message || 'unknown error')
      }`
    })
    .eq('id', jobId);
}

module.exports = { claimJob, releaseClaim, markUncertainHandoff };

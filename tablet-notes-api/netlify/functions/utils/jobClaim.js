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

module.exports = { claimJob, releaseClaim };

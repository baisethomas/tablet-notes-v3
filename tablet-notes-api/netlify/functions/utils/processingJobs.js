/**
 * processing_jobs helpers (TAB-72).
 *
 * Pure/near-pure logic lives here so it is unit-testable — Netlify function
 * handlers themselves have no test harness (CLAUDE.md §10: extract to test).
 */

const JOB_KINDS = Object.freeze({
  TRANSCRIPTION: 'transcription',
  SUMMARY: 'summary'
});

const JOB_STATUS = Object.freeze({
  QUEUED: 'queued',
  SUBMITTED: 'submitted',
  RUNNING: 'running',
  DONE: 'done',
  FAILED: 'failed',
  DEAD: 'dead'
});

/** Statuses that still expect work to happen. */
const ACTIVE_STATUSES = Object.freeze([
  JOB_STATUS.QUEUED,
  JOB_STATUS.SUBMITTED,
  JOB_STATUS.RUNNING
]);

const DEFAULT_MAX_ATTEMPTS = 5;

/**
 * One live job per (sermon, kind). The unique constraint on this value is what
 * makes a double-tap, a client retry after a lost response, and a reaper
 * resubmit all collapse onto the same row instead of billing a second
 * AssemblyAI transcription.
 */
function idempotencyKey(sermonId, kind) {
  if (!sermonId || !kind) {
    throw new Error('idempotencyKey requires sermonId and kind');
  }
  return `${sermonId}:${kind}`;
}

/**
 * Exponential backoff with a cap, in milliseconds.
 * attempt 1 -> 1m, 2 -> 2m, 3 -> 4m, 4 -> 8m, 5 -> 16m, capped at 30m.
 */
function backoffMs(attempt, { baseMs = 60_000, capMs = 1_800_000 } = {}) {
  const safeAttempt = Math.max(1, Number(attempt) || 1);
  return Math.min(baseMs * Math.pow(2, safeAttempt - 1), capMs);
}

function nextAttemptAt(attempt, { now = Date.now(), ...rest } = {}) {
  return new Date(now + backoffMs(attempt, rest)).toISOString();
}

/**
 * Whether a job that a provider still hasn't reported on should be re-driven.
 * A transcription submitted to AssemblyAI more than `staleAfterMs` ago with no
 * terminal webhook is presumed lost (webhook dropped, provider stalled).
 */
function isStale(job, { now = Date.now(), staleAfterMs = 2 * 60 * 60 * 1000 } = {}) {
  if (!job || !ACTIVE_STATUSES.includes(job.status)) return false;
  const reference = job.submitted_at || job.updated_at || job.created_at;
  if (!reference) return false;
  const referenceMs = new Date(reference).getTime();
  if (Number.isNaN(referenceMs)) return false;
  return now - referenceMs >= staleAfterMs;
}

/**
 * Decide what happens to a job after a failed attempt: retry with backoff, or
 * give up permanently ('dead' — a terminal state the client surfaces, never a
 * silent stall).
 */
function planFailure(job, error, { now = Date.now() } = {}) {
  const attempts = (Number(job?.attempts) || 0) + 1;
  const maxAttempts = Number(job?.max_attempts) || DEFAULT_MAX_ATTEMPTS;
  const message = typeof error === 'string' ? error : (error?.message || 'unknown error');

  if (attempts >= maxAttempts) {
    return {
      status: JOB_STATUS.DEAD,
      attempts,
      last_error: message,
      next_attempt_at: null,
      completed_at: new Date(now).toISOString()
    };
  }

  return {
    status: JOB_STATUS.QUEUED,
    attempts,
    last_error: message,
    next_attempt_at: nextAttemptAt(attempts, { now })
  };
}

/**
 * Whether finishing this transcription should chain a summary job.
 * Mirrors summarize.js's own floor: below 50 characters there is nothing
 * meaningful to summarize and the summary job would only fail.
 */
function shouldChainSummary(job, text) {
  if (job?.kind !== JOB_KINDS.TRANSCRIPTION) return false;
  return typeof text === 'string' && text.trim().length >= 50;
}

/**
 * Normalizes an AssemblyAI webhook body to a decision.
 * AssemblyAI posts { transcript_id, status } where status is
 * 'completed' | 'error' (and historically 'transcript.completed' style events).
 */
function interpretWebhook(body) {
  const transcriptId = body?.transcript_id || body?.id || null;
  const rawStatus = String(body?.status || '').toLowerCase();

  if (!transcriptId) {
    return { valid: false, reason: 'missing transcript_id' };
  }

  if (rawStatus === 'completed' || rawStatus === 'transcript.completed') {
    return { valid: true, transcriptId, outcome: 'completed' };
  }
  if (rawStatus === 'error' || rawStatus === 'transcript.error' || rawStatus === 'failed') {
    return {
      valid: true,
      transcriptId,
      outcome: 'error',
      error: body?.error || 'AssemblyAI reported an error'
    };
  }

  return { valid: false, reason: `unhandled status: ${rawStatus || '(none)'}` };
}

/**
 * Constant-time-ish shared-secret comparison for the webhook auth header.
 * Both values are short ASCII secrets; length is compared first, then every
 * byte is examined so the loop does not exit early on the first mismatch.
 */
function secretMatches(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string') return false;
  if (provided.length !== expected.length) return false;
  let mismatch = 0;
  for (let i = 0; i < provided.length; i += 1) {
    mismatch |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return mismatch === 0;
}

module.exports = {
  JOB_KINDS,
  JOB_STATUS,
  ACTIVE_STATUSES,
  DEFAULT_MAX_ATTEMPTS,
  idempotencyKey,
  backoffMs,
  nextAttemptAt,
  isStale,
  planFailure,
  shouldChainSummary,
  interpretWebhook,
  secretMatches
};

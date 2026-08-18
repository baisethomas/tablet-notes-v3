/**
 * processing_jobs helpers (TAB-72).
 *
 * Pure/near-pure logic lives here so it is unit-testable — Netlify function
 * handlers themselves have no test harness (CLAUDE.md §10: extract to test).
 */

const {
  applySermonStageTerminal,
  STATUS_FAILED_PERMANENT
} = require('./sermonStatus');

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
 * The webhook URL we hand the provider, carrying OUR job id.
 *
 * This is what makes the handoff durable (PR #37 review round 3). Resolving a
 * callback purely by `provider_job_id` assumes we successfully wrote that id —
 * but the write can fail, and the submit can time out after AssemblyAI already
 * accepted the audio. In both cases the provider id exists only inside
 * AssemblyAI, the callback arrives for an id we have never seen, and a paid,
 * completed transcription is discarded as "unknown provider job".
 *
 * Our own job id is known BEFORE the submit, so putting it in the callback URL
 * means completion no longer depends on any write of ours succeeding.
 */
function webhookUrlFor(baseUrl, jobId) {
  const root = String(baseUrl || '').replace(/\/+$/, '');
  return `${root}/api/assemblyai-webhook?job=${encodeURIComponent(jobId)}`;
}

/** Reads our job id back off the callback URL. Returns null when absent. */
function jobIdFromWebhookQuery(query) {
  const value = query?.job;
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  // Job ids are uuids; anything else is not ours and must not reach a query.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(trimmed)) {
    return null;
  }
  return trimmed;
}

/**
 * Did a failed submit definitely NOT reach the provider, or is the outcome
 * unknown?
 *
 * This distinction decides whether it is safe to re-queue. A job that was never
 * sent can be retried freely. A job whose fate is unknown must NOT be re-queued:
 * resubmitting bills a second transcription while the first one — which may well
 * be running right now — completes into a row nobody is waiting on.
 *
 * Only failures that are provably local count as 'not-sent': an open circuit
 * breaker (the request was never attempted) and a connection that never
 * established. A timeout is explicitly NOT in that set — the request may have
 * been received and answered slowly.
 */
function classifySubmitFailure(error) {
  const message = String(error?.message || error || '').toLowerCase();

  if (message.includes('circuit breaker')) return 'not-sent';
  if (
    message.includes('enotfound') ||
    message.includes('econnrefused') ||
    message.includes('getaddrinfo')
  ) {
    return 'not-sent';
  }

  return 'uncertain';
}

/**
 * How long a job with an uncertain provider handoff is left alone before it is
 * treated as never-sent and re-queued.
 *
 * Generous on purpose. The webhook carries our job id, so a submission that DID
 * land completes normally within minutes regardless of what we recorded — this
 * window only governs the genuinely-lost case. Retrying a stuck sermon late is
 * recoverable; billing twice and orphaning a paid transcription is not.
 */
const HANDOFF_GRACE_MS = 3 * 60 * 60 * 1000;

/**
 * The outer bound on an unresolvable handoff (PR #37 review round 5).
 *
 * If we cannot determine whether the provider has this audio — the list call
 * keeps failing, or the scan can't reach far enough back — there is no safe
 * automatic action left: resubmitting may double-bill, and waiting forever is
 * the silent stall this whole table exists to prevent. Past this bound the job
 * is marked `dead`, which the client surfaces, so the outcome is a visible
 * failure a person can retry rather than either of those.
 */
const HANDOFF_ABANDON_MS = 24 * 60 * 60 * 1000;

/**
 * Has a backwards scan through the provider's transcripts gone far enough to
 * prove absence?
 *
 * Transcripts list newest-first, so once a page contains anything older than
 * the moment we submitted, every remaining page is older still and the audio
 * genuinely is not there. Anything short of that is "not found yet", NOT proof
 * — treating a bounded page as proof is what would re-queue an accepted
 * submission and bill it twice.
 */
function scanReachedCutoff(transcripts, cutoff) {
  if (!Array.isArray(transcripts) || transcripts.length === 0) return true;

  const cutoffMs = new Date(cutoff).getTime();
  if (Number.isNaN(cutoffMs)) return true;

  let oldest = Infinity;
  for (const transcript of transcripts) {
    const created = new Date(transcript?.created || NaN).getTime();
    if (!Number.isNaN(created)) oldest = Math.min(oldest, created);
  }

  // No usable timestamps: we cannot claim to have reached the cutoff.
  if (oldest === Infinity) return false;
  return oldest < cutoffMs;
}

/**
 * A job stuck in 'submitted' with no provider id: has its grace window expired?
 * Until it has, the reaper must leave it alone rather than resubmit.
 */
function handoffGraceExpired(job, { now = Date.now(), graceMs = HANDOFF_GRACE_MS } = {}) {
  const reference = job?.submitted_at || job?.updated_at || job?.created_at;
  if (!reference) return true;
  const referenceMs = new Date(reference).getTime();
  if (Number.isNaN(referenceMs)) return true;
  return now - referenceMs >= graceMs;
}

/**
 * Find this job's transcription among the provider's recent transcripts, by the
 * one thing both sides agree on: the storage path of the audio (PR #37 review
 * round 4).
 *
 * This is what turns "the grace window expired, so resubmit and hope" into an
 * actual answer. A signed URL is re-minted per submit, so the tokens differ —
 * but the object path inside it does not, which makes it a usable join key.
 *
 * When several transcripts match (a duplicate submitted before this reconcile
 * logic existed), the newest is adopted rather than returning nothing: adopting
 * one of two existing jobs is strictly better than creating a third.
 */
function matchProviderTranscript(transcripts, job) {
  const path = job?.audio_file_path;
  if (!path || !Array.isArray(transcripts)) return null;

  const matches = transcripts.filter((transcript) => {
    const url = transcript?.audio_url;
    if (typeof url !== 'string') return false;
    let decoded = url;
    try {
      decoded = decodeURIComponent(url);
    } catch (_) {
      // Malformed encoding: fall back to the raw string rather than throwing.
    }
    return decoded.includes(path);
  });

  if (matches.length === 0) return null;
  if (matches.length === 1) return matches[0];

  return matches
    .slice()
    .sort((a, b) => new Date(b?.created || 0).getTime() - new Date(a?.created || 0).getTime())[0];
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

/**
 * Whether an existing job should be handed back untouched rather than revived
 * (TAB-85).
 *
 * A `dead` job has already burned every attempt. Reviving it on an automatic
 * sweep is what made an unusable recording retry forever: the client re-POSTs
 * every pending/failed sermon each launch, the revive reset `attempts` to 0,
 * and the reaper spent five more provider calls before it died again.
 *
 * A deliberate retry may still revive it. Nothing else may.
 *
 * Extracted here rather than written inline in `jobs.js` because functions are
 * not directly testable (CLAUDE.md §10) — and the first version of this logic
 * shipped a `ReferenceError` past a green suite precisely because the test
 * asserted on the source text instead of calling anything.
 */
function isExhaustedWithoutRetry(existing, retry) {
  return Boolean(existing) && existing.status === JOB_STATUS.DEAD && retry !== true;
}

/**
 * Writes a failed attempt to the ledger, and stops the sermon stage when the
 * job has run out of attempts (TAB-85).
 *
 * Every failure path used to update `processing_jobs` directly, so the ledger
 * could say `dead` while the sermon still said `pending`. That mismatch is the
 * whole issue: the client re-dispatched the sermon on every sweep, and the user
 * watched a spinner for work that had been abandoned days earlier.
 *
 * One seam, for the same reason completeTranscriptionJob is one: the two
 * completion paths had already drifted apart once, and there are five failure
 * call sites here.
 *
 * Stopping the stage is deliberately NOT conditional on why the provider
 * failed. Every dead job in production carries the same generic sentence, and
 * matching on a provider's prose would be guesswork. "We tried max_attempts
 * times and stopped" is a fact this code owns, and it is the fact the user
 * needs — a Retry remains available, it just is not automatic any more.
 */
async function persistJobFailure({ supabase, job, failure, logger }) {
  const { error } = await supabase.from('processing_jobs').update(failure).eq('id', job.id);

  if (error) {
    logger?.error?.('Failed to record job failure', { jobId: job?.id }, error);
    return { error };
  }

  if (failure?.status !== JOB_STATUS.DEAD) return { error: null };

  // Non-fatal, like every other sermon-status write: the ledger is already
  // correct, and a stale status is recoverable where a failure here would send
  // an exhausted job back around the loop. buildSermonStatusPatch throws on an
  // unrecognised stage, so this is caught rather than trusted — a job kind that
  // has no sermon column must not take down the failure path itself.
  try {
    await applySermonStageTerminal({
      supabase,
      sermonId: job?.sermon_id,
      stage: job?.kind,
      status: STATUS_FAILED_PERMANENT,
      logger
    });
  } catch (statusError) {
    logger?.error?.('Could not stop the sermon stage for a dead job', {
      jobId: job?.id,
      kind: job?.kind,
      error: statusError.message
    });
  }

  return { error: null };
}

module.exports = {
  isExhaustedWithoutRetry,
  JOB_KINDS,
  JOB_STATUS,
  ACTIVE_STATUSES,
  DEFAULT_MAX_ATTEMPTS,
  HANDOFF_GRACE_MS,
  HANDOFF_ABANDON_MS,
  scanReachedCutoff,
  idempotencyKey,
  backoffMs,
  nextAttemptAt,
  isStale,
  planFailure,
  persistJobFailure,
  webhookUrlFor,
  jobIdFromWebhookQuery,
  classifySubmitFailure,
  handoffGraceExpired,
  matchProviderTranscript,
  shouldChainSummary,
  interpretWebhook,
  secretMatches
};

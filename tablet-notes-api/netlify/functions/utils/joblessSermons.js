/**
 * Reconciling sermons that have no processing_jobs row (TAB-122).
 *
 * The durable pipeline has two sweeps and both key off a job row: the reaper
 * iterates `processing_jobs`, and the client re-asks POST /api/jobs only for
 * sermons it still sees as `pending`/`failed`. A sermon the legacy queue left
 * at `processing`, or whose job request never reached the server, therefore
 * has no owner at all — it reads "processing" forever with no error and no
 * Retry. Measured in production on 2026-10-25: 19 transcription stages and
 * 14 summary stages in that state, across 7 users, the oldest from May.
 *
 * The server is the only participant guaranteed to be present, and a server
 * fix heals every shipped build (docs/OPERATING-MANUAL.md §6), so the reaper
 * fills in the missing rows. Everything after that is the existing path: the
 * queued job is submitted, dead audio dies honestly, and TAB-85 writes
 * `failed_permanent` back onto the sermon.
 *
 * Pure logic lives here so it is unit-testable; the reaper only wires it up.
 */

const { isTerminalStatus, STATUS_COMPLETE } = require('./sermonStatus');
const { isOwnedObjectPath } = require('./audioObjectPath');
const { JOB_KINDS, JOB_STATUS, idempotencyKey } = require('./processingJobs');

/**
 * How long a sermon must have sat untouched before the server steps in. A
 * live client needs time to push its own job request after upload; thirty
 * minutes is far past that and far short of the hours-to-months the stuck
 * rows have waited.
 */
const RECONCILE_MIN_AGE_MS = 30 * 60 * 1000;

/**
 * Jobs created per sweep. The backlog is one-time and the reaper runs every
 * five minutes, so a small cap clears it within the hour without handing the
 * provider thirty files at once.
 */
const RECONCILE_BATCH_LIMIT = 10;

const RECONCILED_LAST_ERROR = 'reconciled: sermon had no job row';

/**
 * Which stage, if any, still expects work. Transcription first: a summary
 * cannot run without a transcript, and a transcription that stopped without
 * speech has nothing to summarize.
 */
function missingStageFor(sermon) {
  if (!sermon || typeof sermon !== 'object') return null;

  const transcription = sermon.transcription_status;
  if (!isTerminalStatus(transcription)) return JOB_KINDS.TRANSCRIPTION;
  // Stopped any other way (no_speech, failed_permanent) means no summary.
  if (transcription !== STATUS_COMPLETE) return null;

  if (!isTerminalStatus(sermon.summary_status)) return JOB_KINDS.SUMMARY;
  return null;
}

function parseUpdatedAt(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

function hasTranscriptText(sermon) {
  return typeof sermon.transcript_text === 'string' && sermon.transcript_text.trim().length > 0;
}

/**
 * Decide what the reconciler does with one job-less sermon.
 *
 *   { action: 'create_job',    stage }  — write a queued job row
 *   { action: 'mark_complete', stage }  — the transcript already exists; advance
 *                                         the stage instead of paying for it again
 *   { action: 'skip',          reason } — leave it alone; the reason is logged
 *
 * The refusals are deliberate and ordered: a stopped sermon is not touched; a
 * fresh one belongs to its client; a sermon with no audio or another user's
 * audio is never processed with the service key (TAB-84: authorize the stored
 * path on every read, because rows written before the write-side check still
 * exist).
 */
function classifyJoblessSermon(sermon, { now = Date.now(), minAgeMs = RECONCILE_MIN_AGE_MS } = {}) {
  if (!sermon || typeof sermon !== 'object' || Array.isArray(sermon)) {
    return { action: 'skip', reason: 'invalid' };
  }

  const stage = missingStageFor(sermon);
  if (!stage) return { action: 'skip', reason: 'terminal' };

  const updatedAt = parseUpdatedAt(sermon.updated_at);
  if (updatedAt === null || now - updatedAt < minAgeMs) {
    return { action: 'skip', reason: 'fresh' };
  }

  const path = typeof sermon.audio_file_path === 'string' ? sermon.audio_file_path.trim() : '';
  if (!path) return { action: 'skip', reason: 'no_audio' };
  if (!sermon.user_id || !isOwnedObjectPath(path, sermon.user_id)) {
    return { action: 'skip', reason: 'foreign_path' };
  }

  if (!sermon.id || !sermon.local_id) return { action: 'skip', reason: 'no_local_id' };

  // Status-only poison: the transcript landed but the stage never advanced
  // (the server-side counterpart of the client's TAB-94 repair). Submitting
  // the audio again would bill AssemblyAI for a result already in the table,
  // so the stage is advanced instead; the next sweep then sees a complete
  // transcription and reconciles the summary stage on its own.
  if (stage === JOB_KINDS.TRANSCRIPTION && hasTranscriptText(sermon)) {
    return { action: 'mark_complete', stage };
  }

  return { action: 'create_job', stage };
}

/**
 * The row the reaper inserts. Identical in shape to what POST /api/jobs
 * writes, including the idempotency key, so a client request landing at the
 * same moment collapses onto this row (unique constraint) instead of creating
 * a second one. `last_error` carries a marker rather than nothing so the
 * ledger shows which rows the server had to fill in.
 */
function buildReconciledJobPayload(sermon, stage) {
  if (!Object.values(JOB_KINDS).includes(stage)) {
    throw new Error(`unknown processing stage: ${stage}`);
  }
  return {
    user_id: sermon.user_id,
    sermon_id: sermon.id,
    sermon_local_id: sermon.local_id,
    kind: stage,
    status: JOB_STATUS.QUEUED,
    audio_file_path: sermon.audio_file_path,
    idempotency_key: idempotencyKey(sermon.id, stage),
    attempts: 0,
    last_error: RECONCILED_LAST_ERROR
  };
}

/**
 * Turn one sweep's candidates into a plan: rows to create (capped, newest
 * first), stages to repair (uncapped — a status write costs nothing), and
 * every skip with its reason.
 *
 * `existingJobs` is checked by (sermon, kind) regardless of status. A `dead`
 * row is still a row: the automatic path must never resurrect exhausted work
 * (TAB-85); that is what the Retry button is for.
 */
function planJoblessReconciliation({
  sermons,
  existingJobs,
  now = Date.now(),
  minAgeMs = RECONCILE_MIN_AGE_MS,
  limit = RECONCILE_BATCH_LIMIT
} = {}) {
  const plan = { create: [], markComplete: [], skipped: [], deferred: 0 };
  if (!Array.isArray(sermons)) return plan;

  const taken = new Set();
  for (const job of Array.isArray(existingJobs) ? existingJobs : []) {
    if (job && job.sermon_id && job.kind) taken.add(`${job.sermon_id}:${job.kind}`);
  }

  const ordered = [...sermons].sort((a, b) => {
    const am = parseUpdatedAt(a?.updated_at) ?? 0;
    const bm = parseUpdatedAt(b?.updated_at) ?? 0;
    return bm - am;
  });

  for (const sermon of ordered) {
    const decision = classifyJoblessSermon(sermon, { now, minAgeMs });

    if (decision.action === 'skip') {
      plan.skipped.push({ sermon_id: sermon?.id ?? null, reason: decision.reason });
      continue;
    }

    if (taken.has(`${sermon.id}:${decision.stage}`)) {
      plan.skipped.push({ sermon_id: sermon.id, reason: 'has_job' });
      continue;
    }

    if (decision.action === 'mark_complete') {
      plan.markComplete.push({ sermon_id: sermon.id, stage: decision.stage });
      continue;
    }

    if (plan.create.length >= limit) {
      plan.deferred += 1;
      continue;
    }
    plan.create.push(buildReconciledJobPayload(sermon, decision.stage));
  }

  return plan;
}

module.exports = {
  RECONCILE_MIN_AGE_MS,
  RECONCILE_BATCH_LIMIT,
  RECONCILED_LAST_ERROR,
  missingStageFor,
  classifyJoblessSermon,
  planJoblessReconciliation,
  buildReconciledJobPayload
};

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
const { JOB_KINDS, JOB_STATUS, idempotencyKey, shouldChainSummary } = require('./processingJobs');

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

/**
 * Candidates read per page, and how many pages one sweep may read. The scan
 * pages because some candidates can never be acted on (they already have a
 * job, or their transcript is not on the server) and they stay candidates
 * forever: a single fixed window fills up with them and the sermons behind it
 * are never seen. 20 x 50 is far more candidates than exist; hitting the page
 * limit is logged, never silent.
 */
const RECONCILE_PAGE_SIZE = 50;
const RECONCILE_MAX_PAGES = 20;

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

/** Same floor the normal pipeline uses when it decides whether to chain a summary. */
function isLongEnoughToSummarize(text) {
  return shouldChainSummary({ kind: JOB_KINDS.TRANSCRIPTION }, text);
}

/**
 * Decide what the reconciler does with one job-less sermon.
 *
 *   { action: 'create_job',     stage }  — write a queued job row
 *   { action: 'mark_complete',  stage }  — the transcript already exists; advance
 *                                          the stage instead of paying for it again
 *   { action: 'mark_too_short', stage }  — the transcript is below the summarizer's
 *                                          floor; stop the summary stage the way
 *                                          the normal pipeline does
 *   { action: 'skip',           reason } — leave it alone; the reason is logged
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

  // A summary job reads the transcript from the server. Queuing one for a
  // transcript that is missing or below the floor only burns its five attempts
  // and stamps `failed_permanent` on a sermon nothing was wrong with.
  //
  // A summary that already exists wins over both checks: the job costs nothing
  // (runSummary marks it done without regenerating) and it is what moves the
  // stage to `complete`.
  if (stage === JOB_KINDS.SUMMARY && sermon.has_summary !== true) {
    // No transcript on the server does not mean no transcript: it may exist
    // only on the device. Nothing here can tell, so the sermon is left alone.
    if (!hasTranscriptText(sermon)) return { action: 'skip', reason: 'no_transcript' };
    if (!isLongEnoughToSummarize(sermon.transcript_text)) {
      return { action: 'mark_too_short', stage };
    }
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
  const plan = emptyPlan();
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

    if (decision.action === 'mark_too_short') {
      plan.markTooShort.push({ sermon_id: sermon.id, stage: decision.stage });
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

function emptyPlan() {
  return { create: [], markComplete: [], markTooShort: [], skipped: [], deferred: 0 };
}

function hasText(row) {
  return typeof row?.text === 'string' && row.text.trim().length > 0;
}

/**
 * Read candidates page by page and build one plan for the sweep.
 *
 * The caller supplies the two reads so this stays testable without a database:
 *
 *   fetchPage({ offset, limit })  -> candidate sermons, in a stable order
 *   fetchContext(sermonIds)       -> { jobs, transcripts, summaries } for them
 *
 * Paging stops when the candidates run out, when the sweep's job batch is
 * full, or at `maxPages`. `exhausted` says whether every candidate was seen,
 * so the caller can log a scan that was cut off rather than hide it.
 *
 * Nothing is written here, so the scan does not move its own pages. Another
 * writer can still move a row out of the filter mid-scan, which shifts the
 * later rows up by one and hides one of them from this sweep; the next sweep
 * sees it. Either read throwing aborts the whole plan: the caller creates nothing,
 * because a job created without knowing whether one exists is the
 * double-billing this avoids.
 */
async function collectJoblessPlan({
  fetchPage,
  fetchContext,
  now = Date.now(),
  minAgeMs = RECONCILE_MIN_AGE_MS,
  limit = RECONCILE_BATCH_LIMIT,
  pageSize = RECONCILE_PAGE_SIZE,
  maxPages = RECONCILE_MAX_PAGES
} = {}) {
  const plan = emptyPlan();
  let scanned = 0;
  let exhausted = false;

  for (let page = 0; page < maxPages; page += 1) {
    const sermons = await fetchPage({ offset: page * pageSize, limit: pageSize });
    if (!Array.isArray(sermons) || sermons.length === 0) {
      exhausted = true;
      break;
    }
    scanned += sermons.length;

    const context = (await fetchContext(sermons.map((s) => s.id))) || {};
    const textBySermon = new Map((context.transcripts || []).map((t) => [t.sermon_id, t.text]));
    const summarized = new Set((context.summaries || []).filter(hasText).map((s) => s.sermon_id));

    const pagePlan = planJoblessReconciliation({
      sermons: sermons.map((s) => ({
        ...s,
        transcript_text: textBySermon.get(s.id) ?? null,
        has_summary: summarized.has(s.id)
      })),
      existingJobs: context.jobs || [],
      now,
      minAgeMs,
      limit: limit - plan.create.length
    });

    plan.create.push(...pagePlan.create);
    plan.markComplete.push(...pagePlan.markComplete);
    plan.markTooShort.push(...pagePlan.markTooShort);
    plan.skipped.push(...pagePlan.skipped);
    plan.deferred += pagePlan.deferred;

    if (sermons.length < pageSize) {
      exhausted = true;
      break;
    }
    if (plan.create.length >= limit) break;
  }

  return { plan, scanned, exhausted };
}

module.exports = {
  RECONCILE_MIN_AGE_MS,
  RECONCILE_BATCH_LIMIT,
  RECONCILE_PAGE_SIZE,
  RECONCILE_MAX_PAGES,
  RECONCILED_LAST_ERROR,
  missingStageFor,
  classifyJoblessSermon,
  planJoblessReconciliation,
  collectJoblessPlan,
  buildReconciledJobPayload
};

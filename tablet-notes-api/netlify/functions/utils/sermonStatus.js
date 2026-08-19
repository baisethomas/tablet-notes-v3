/**
 * Writing a completed stage back onto the sermon row (TAB-89).
 *
 * The durable pipeline persisted transcripts and summaries but never touched
 * `sermons.transcription_status` / `summary_status`. The only thing that ever
 * corrected them was a **live client**: `ProcessingObserver` sees the job go
 * terminal over Realtime and pushes the status up on its next sync.
 *
 * So the status was right exactly when the app happened to be running, and
 * stale in the one case the durable pipeline exists for — work finishing while
 * the client is away. Measured in production: 17 sermons with a `done`
 * transcription job and a real transcript, **zero** of them reading
 * `complete`. Users see "transcription pending" on work that finished weeks
 * ago, and the client re-dispatches those sermons on every sweep.
 *
 * The server is the right owner because it is the only participant guaranteed
 * to be present when the job finishes. Realtime stays as the fast in-app
 * update, not the source of truth.
 */

const SERMON_STAGE_COLUMNS = {
  transcription: 'transcription_status',
  summary: 'summary_status'
};

const STATUS_COMPLETE = 'complete';
/** Transcription succeeded and the provider returned no speech at all. */
const STATUS_NO_SPEECH = 'no_speech';
/** The pipeline exhausted its attempts and stopped trying (TAB-85). */
const STATUS_FAILED_PERMANENT = 'failed_permanent';

/**
 * The states a stage can STOP in.
 *
 * Before TAB-85 there was exactly one — `complete` — so the only way the
 * pipeline could end was successfully. A recording that could never transcribe
 * and one that transcribed to nothing both sat at `pending`: a spinner the user
 * could not clear, and a sermon the client re-dispatched on every sweep.
 *
 * These are server-owned. A client may not write itself out of, or between,
 * them — see isForbiddenStageRegression.
 */
const TERMINAL_STATUSES = [STATUS_COMPLETE, STATUS_NO_SPEECH, STATUS_FAILED_PERMANENT];

function isTerminalStatus(status) {
  return typeof status === 'string' && TERMINAL_STATUSES.includes(status);
}

/**
 * Builds the `sermons` patch for a finished stage.
 *
 * Pure so the column mapping is testable without a database — getting the
 * column name wrong is exactly the kind of silent no-op this issue was.
 *
 * @param {'transcription'|'summary'} stage
 * @param {string} [title] Optional generated title, folded into the same write
 *   so the summary path does one update instead of two.
 */
function buildSermonStatusPatch({ stage, status = STATUS_COMPLETE, title, now = new Date().toISOString() }) {
  const column = SERMON_STAGE_COLUMNS[stage];
  if (!column) {
    throw new Error(`buildSermonStatusPatch: unknown stage "${stage}"`);
  }
  // Only the server writes these, and only ever a state the pipeline can stop
  // in. Anything else here is a bug in the caller, not a value to persist.
  if (!isTerminalStatus(status)) {
    throw new Error(`buildSermonStatusPatch: "${status}" is not a terminal status`);
  }

  const patch = { [column]: status, updated_at: now };
  // Only set a title when there is one — an empty string would wipe whatever
  // the user or an earlier stage already put there.
  if (typeof title === 'string' && title.trim()) {
    patch.title = title;
  }
  return patch;
}

/**
 * Applies the patch, returning the Supabase error rather than throwing.
 *
 * Deliberately **non-fatal** for the caller. By the time this runs the
 * transcript or summary is already durably written, and failing the job here
 * would send it back through a retry that can re-bill a provider call. A stale
 * status is recoverable — the client still corrects it on its next Realtime
 * event or sync — whereas a paid re-transcription is not. The error is
 * returned so the caller logs it loudly instead of dropping it.
 */
async function applySermonStageTerminal({
  supabase,
  sermonId,
  stage,
  status = STATUS_COMPLETE,
  title,
  logger,
  // When true, the write only lands while the stage has NOT already stopped.
  //
  // The failure path needs this and the success path must not have it. A dead
  // job whose stage already reads `complete` is pure bookkeeping — the summary
  // exists; the ledger update failed — and stamping `failed_permanent` over it
  // would hide a saved result behind an error screen (PR #52 review). Whereas
  // `complete` must stay unconditional: a job that eventually succeeds after
  // the stage was stopped is exactly the write that should win.
  onlyIfNotTerminal = false
} = {}) {
  if (!sermonId) return { error: null, patch: null, applied: false };

  const patch = buildSermonStatusPatch({ stage, status, title });
  const column = SERMON_STAGE_COLUMNS[stage];

  if (onlyIfNotTerminal) {
    const { data, error } = await supabase
      .from('sermons')
      .update(patch)
      .eq('id', sermonId)
      .or(stageNotTerminalPredicate(column))
      .select('id');

    if (error) {
      logger?.error?.('Failed to write sermon stage status', { sermonId, stage, status }, error);
      return { error, patch, applied: false };
    }
    const applied = Array.isArray(data) && data.length > 0;
    if (!applied) {
      logger?.info?.('Stage already terminal; left as-is', { sermonId, stage, status });
    }
    return { error: null, patch, applied };
  }

  const { error } = await supabase.from('sermons').update(patch).eq('id', sermonId);

  if (error) {
    logger?.error?.('Failed to write sermon stage status', { sermonId, stage, status }, error);
  }
  return { error: error || null, patch, applied: !error };
}

/**
 * Whether an incoming stage status must be refused (TAB-90).
 *
 * The server marks a stage `complete` when a durable job finishes. A client can
 * then undo that: `SermonSyncRemoteGateway` includes both stage statuses in the
 * push whenever the metadata scope is dirty (an offline title edit is enough),
 * sync pushes before it pulls, and this endpoint accepted them unconditionally.
 * The device's stale `pending` won, and because the job is already terminal no
 * further Realtime event ever corrected it.
 *
 * The first version of this guard compared timestamps, on the theory that a
 * deliberate change happens *after* the server's write and a stale push before
 * it. That was wrong, and review caught it: `Sermon.markPendingSync` stamps
 * `updatedAt = Date()` for **any** dirty scope, so editing a title gives the
 * whole row a fresh timestamp and carries the stale stage status through on its
 * coat-tails — exactly the sequence this issue is about.
 *
 * So the rule is simply that a client may not walk a completed stage backwards.
 * That is safe because there is no legitimate client-initiated path from
 * `complete` to anything else: the retry affordance in `SermonDetailView` is
 * only reachable while the local status is `processing`, `failed`, or
 * `pending`. When a client that believes a stage failed retries one the server
 * has since completed, keeping `complete` is the *desired* outcome — the
 * transcript already exists, and the client lands it on its next pull instead
 * of re-billing the provider.
 *
 * No clocks are involved, which is the point: the previous version's behaviour
 * depended on device time being honest and ordered against the server's.
 *
 * Known limit: a `complete` the server wrote in error cannot be walked back by
 * a client. Recovering from that needs a server-side path, which is where
 * terminal states (TAB-85) will live.
 */
function isForbiddenStageRegression({ serverStatus, incomingStatus }) {
  if (incomingStatus === undefined || incomingStatus === null) return false;
  // Only a stage the server has already stopped needs protecting.
  if (!isTerminalStatus(serverStatus)) return false;
  // Re-sending the same value is a no-op, not a regression. Anything else —
  // including one terminal state for another — is the client overruling a
  // decision only the server is in a position to make.
  return incomingStatus !== serverStatus;
}

/**
 * Decides what `update-sermon` should do with the stage statuses in a push.
 *
 * Pure, so the decision is testable without a database — the previous round of
 * tests asserted on the *source text* of the endpoint, which proves only that
 * certain characters are present and would have happily passed a broken
 * implementation.
 *
 * Returns the writes to apply and the columns refused. A value the server
 * already holds produces no write at all: that keeps the common metadata push
 * to a single statement, and it means a stage that completes between the read
 * and the write is left alone rather than being restated from a stale snapshot.
 */
function planStageStatusWrites({ incoming = {}, server = {} } = {}) {
  const writes = [];
  const dropped = [];

  for (const [field, column] of [
    ['transcriptionStatus', SERMON_STAGE_COLUMNS.transcription],
    ['summaryStatus', SERMON_STAGE_COLUMNS.summary]
  ]) {
    const incomingStatus = incoming[field];
    if (incomingStatus === undefined || incomingStatus === null) continue;

    const serverStatus = server[column];
    if (incomingStatus === serverStatus) continue;

    if (isForbiddenStageRegression({ serverStatus, incomingStatus })) {
      dropped.push(column);
      continue;
    }
    writes.push({ column, value: incomingStatus });
  }

  return { writes, dropped };
}

/**
 * PostgREST filter making a stage write a compare-and-set.
 *
 * The snapshot this decision was made from is already stale by the time the
 * write goes out: a job finishing in that window would otherwise be clobbered
 * by the client's value, and since the job is terminal nothing would correct
 * it. Anding this onto the update means the row is only touched while the
 * column is still not `complete`.
 *
 * The null branch matters — `status <> 'complete'` is NULL, not true, for a row
 * where the column was never set, so a bare `neq` would silently match nothing.
 */
function stageNotTerminalPredicate(column) {
  // `and(...)` nested inside the top-level `or` so this reads as
  //   column IS NULL OR (column <> each terminal state)
  // rather than the useless "differs from at least one of them".
  const notAny = TERMINAL_STATUSES.map((s) => `${column}.neq.${s}`).join(',');
  return `${column}.is.null,and(${notAny})`;
}

/**
 * Applies the planned stage writes, returning the columns that did not land.
 *
 * Lives here rather than inline in the endpoint so the compare-and-set can be
 * tested against a fake client: the filter is the entire point of this code,
 * and a test that reads the endpoint's source proves only that some characters
 * are present.
 *
 * A write that matches zero rows is not an error — it means the stage reached
 * `complete` after the caller took its snapshot, so the server's value is the
 * newer truth and the client's is reported as dropped.
 */
async function applyStageStatusWrites({ supabase, sermonId, userId, writes = [], logger }) {
  const dropped = [];

  for (const { column, value } of writes) {
    const { data: applied, error } = await supabase
      .from('sermons')
      .update({ [column]: value })
      .eq('id', sermonId)
      .eq('user_id', userId)
      .or(stageNotTerminalPredicate(column))
      .select('id');

    if (error) {
      logger?.warn?.('Failed to apply stage status', { sermonId, column, error: error.message });
      continue;
    }
    if (!applied || applied.length === 0) {
      dropped.push(column);
      logger?.info?.('Stage completed while the update was in flight; kept the server value', {
        sermonId,
        column
      });
    }
  }

  return { dropped };
}

module.exports = {
  buildSermonStatusPatch,
  applySermonStageTerminal,
  isForbiddenStageRegression,
  planStageStatusWrites,
  stageNotTerminalPredicate,
  applyStageStatusWrites,
  SERMON_STAGE_COLUMNS,
  STATUS_COMPLETE,
  STATUS_NO_SPEECH,
  STATUS_FAILED_PERMANENT,
  TERMINAL_STATUSES,
  isTerminalStatus
};

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
function buildSermonStatusPatch({ stage, title, now = new Date().toISOString() }) {
  const column = SERMON_STAGE_COLUMNS[stage];
  if (!column) {
    throw new Error(`buildSermonStatusPatch: unknown stage "${stage}"`);
  }

  const patch = { [column]: STATUS_COMPLETE, updated_at: now };
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
async function applySermonStageComplete({ supabase, sermonId, stage, title, logger }) {
  if (!sermonId) return { error: null, patch: null };

  const patch = buildSermonStatusPatch({ stage, title });
  const { error } = await supabase.from('sermons').update(patch).eq('id', sermonId);

  if (error) {
    logger?.error?.('Failed to write sermon stage status', { sermonId, stage }, error);
  }
  return { error: error || null, patch };
}

module.exports = {
  buildSermonStatusPatch,
  applySermonStageComplete,
  SERMON_STAGE_COLUMNS,
  STATUS_COMPLETE
};

/**
 * Builds the `summaries` row the durable pipeline persists (TAB-81).
 *
 * Extracted so the column contract is testable: the reaper is a Netlify
 * function and cannot be unit-tested directly, and the bug this fixes was
 * exactly a missing column that no test could have caught.
 *
 * `summaries` requires (NOT NULL, no default) — confirmed against the live
 * PostgREST schema, not inferred from the Swift model:
 *   local_id, sermon_id, user_id, title, text, type, status
 *
 * The original reaper upsert omitted BOTH `type` and `title`, so every summary
 * job failed with a not-null violation and retried into `dead`.
 */

const REQUIRED_COLUMNS = [
  'local_id',
  'sermon_id',
  'user_id',
  'title',
  'text',
  'type',
  'status'
];

/**
 * `type` in production overwhelmingly holds the sermon's service type
 * ('Sermon', 'Sunday Service', 'Bible Study', 'Conference') rather than a
 * summary format — only 4 of 312 rows use 'devotional'. So mirror the service
 * type, and never overwrite a type an existing row already carries.
 */
function buildSummaryUpsertRow({
  localId,
  sermonId,
  userId,
  title,
  text,
  serviceType,
  existingSummary,
  now = new Date().toISOString()
}) {
  return {
    local_id: existingSummary?.local_id || localId,
    sermon_id: sermonId,
    user_id: userId,
    // Prefer the freshly generated title; fall back to whatever the row already
    // had. The column is NOT NULL but does allow empty, so '' is a valid last
    // resort — it must never be null.
    title: title || existingSummary?.title || '',
    text,
    type: existingSummary?.type || serviceType || 'Sermon',
    status: 'complete',
    updated_at: now
  };
}

/**
 * Returns the names of any required column that is null/undefined. Lets the
 * caller fail with a precise message instead of a raw Postgres constraint
 * error, and keeps the contract checkable in tests.
 */
function missingRequiredSummaryColumns(row) {
  return REQUIRED_COLUMNS.filter(
    (column) => row[column] === null || row[column] === undefined
  );
}

module.exports = {
  buildSummaryUpsertRow,
  missingRequiredSummaryColumns,
  REQUIRED_SUMMARY_COLUMNS: REQUIRED_COLUMNS
};

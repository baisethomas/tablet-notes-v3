const test = require('node:test');
const assert = require('node:assert');

const {
  buildSummaryUpsertRow,
  missingRequiredSummaryColumns,
  REQUIRED_SUMMARY_COLUMNS
} = require('../summaryRow');

// TAB-81: the durable pipeline's summary upsert omitted `type` and `title`,
// both NOT NULL in production. Every summary job failed with a not-null
// violation and retried into `dead` — 100% failure, invisible until a real job
// ran through it.

test('row includes every NOT NULL column the summaries table requires', () => {
  const row = buildSummaryUpsertRow({
    localId: 'local-1',
    sermonId: 'sermon-1',
    userId: 'user-1',
    title: 'Transition from Wilderness to Promise',
    text: 'A summary body.',
    serviceType: 'Sunday Service'
  });

  assert.deepStrictEqual(missingRequiredSummaryColumns(row), []);
  for (const column of REQUIRED_SUMMARY_COLUMNS) {
    assert.ok(row[column] !== null && row[column] !== undefined, `${column} must be set`);
  }
});

test('the exact payload that shipped is caught as missing type and title', () => {
  // Reproduces the pre-fix upsert object verbatim.
  const shipped = {
    local_id: 'local-1',
    sermon_id: 'sermon-1',
    user_id: 'user-1',
    text: 'A summary body.',
    status: 'complete',
    updated_at: new Date(0).toISOString()
  };

  assert.deepStrictEqual(missingRequiredSummaryColumns(shipped).sort(), ['title', 'type']);
});

test('type mirrors the service type, matching how production uses the column', () => {
  // Prod: Sermon 194, Sunday Service 79, Bible Study 22, Conference 13,
  // devotional 4 — the column holds the service type, not a summary format.
  const row = buildSummaryUpsertRow({
    localId: 'l', sermonId: 's', userId: 'u',
    title: 'T', text: 'body', serviceType: 'Bible Study'
  });
  assert.strictEqual(row.type, 'Bible Study');
});

test('an existing row keeps its own type and local_id when re-summarized', () => {
  const row = buildSummaryUpsertRow({
    localId: 'freshly-generated',
    sermonId: 's', userId: 'u',
    title: 'New Title',
    text: 'new body',
    serviceType: 'Conference',
    existingSummary: { local_id: 'original-local', title: 'Old Title', type: 'Sunday Service' }
  });

  assert.strictEqual(row.local_id, 'original-local', 'must not orphan the client row');
  assert.strictEqual(row.type, 'Sunday Service', 'must not rewrite the established type');
  assert.strictEqual(row.title, 'New Title', 'a fresh title should win');
});

test('a missing generated title falls back rather than going null', () => {
  const withExisting = buildSummaryUpsertRow({
    localId: 'l', sermonId: 's', userId: 'u',
    title: null, text: 'body', serviceType: 'Sermon',
    existingSummary: { local_id: 'l', title: 'Kept Title', type: 'Sermon' }
  });
  assert.strictEqual(withExisting.title, 'Kept Title');

  const noExisting = buildSummaryUpsertRow({
    localId: 'l', sermonId: 's', userId: 'u',
    title: null, text: 'body', serviceType: 'Sermon'
  });
  // NOT NULL permits empty; it must never be null.
  assert.strictEqual(noExisting.title, '');
  assert.deepStrictEqual(missingRequiredSummaryColumns(noExisting), []);
});

test('type falls back to Sermon when the service type is unknown', () => {
  const row = buildSummaryUpsertRow({
    localId: 'l', sermonId: 's', userId: 'u',
    title: 'T', text: 'body', serviceType: undefined
  });
  assert.strictEqual(row.type, 'Sermon');
});

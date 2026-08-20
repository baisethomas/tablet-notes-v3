const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  clearFailedPermanentStage,
  STATUS_FAILED_PERMANENT,
  STATUS_NO_SPEECH,
  STATUS_TOO_SHORT
} = require('../sermonStatus');

// TAB-91. Entry into failed_permanent is server-owned. Exit must be too —
// TAB-90 refuses a client push out of any terminal state, which is why the
// old Retry button became a silent no-op after #52.

function fakeSupabase({ selectResult = [{ id: 'sermon-1' }] } = {}) {
  const writes = [];
  return {
    writes,
    from(table) {
      assert.equal(table, 'sermons');
      return {
        update(patch) {
          const rec = { patch, filters: [] };
          const chain = {
            eq(column, value) {
              rec.filters.push(['eq', column, value]);
              return chain;
            },
            async select() {
              writes.push(rec);
              return { data: selectResult, error: null };
            }
          };
          return chain;
        }
      };
    }
  };
}

test('a deliberate retry clears failed_permanent back to pending', async () => {
  const supabase = fakeSupabase();
  const result = await clearFailedPermanentStage({
    supabase,
    sermonId: 'sermon-1',
    stage: 'transcription',
    now: '2026-08-20T12:00:00.000Z'
  });

  assert.equal(result.applied, true);
  assert.deepEqual(supabase.writes[0].patch, {
    transcription_status: 'pending',
    updated_at: '2026-08-20T12:00:00.000Z'
  });
  assert.deepEqual(supabase.writes[0].filters, [
    ['eq', 'id', 'sermon-1'],
    ['eq', 'transcription_status', STATUS_FAILED_PERMANENT]
  ]);
});

test('a summary retry clears only the summary column', async () => {
  const supabase = fakeSupabase();
  await clearFailedPermanentStage({
    supabase,
    sermonId: 'sermon-1',
    stage: 'summary',
    now: '2026-08-20T12:00:00.000Z'
  });

  assert.equal(supabase.writes[0].patch.summary_status, 'pending');
  assert.ok(!('transcription_status' in supabase.writes[0].patch));
  assert.deepEqual(supabase.writes[0].filters[1], [
    'eq',
    'summary_status',
    STATUS_FAILED_PERMANENT
  ]);
});

test('no_speech and too_short are never cleared by a retry', async () => {
  // The compare is equality on failed_permanent. A row sitting at no_speech
  // or too_short simply does not match — and must not, or Retry would lie.
  for (const other of [STATUS_NO_SPEECH, STATUS_TOO_SHORT, 'complete', 'pending']) {
    assert.notEqual(other, STATUS_FAILED_PERMANENT);
  }

  const supabase = fakeSupabase({ selectResult: [] });
  const result = await clearFailedPermanentStage({
    supabase,
    sermonId: 'sermon-1',
    stage: 'transcription'
  });

  assert.equal(result.applied, false);
  assert.deepEqual(supabase.writes[0].filters[1], [
    'eq',
    'transcription_status',
    STATUS_FAILED_PERMANENT
  ]);
});

test('a missing sermon id is a no-op, not a throw', async () => {
  const supabase = fakeSupabase();
  const result = await clearFailedPermanentStage({
    supabase,
    sermonId: null,
    stage: 'transcription'
  });
  assert.equal(result.applied, false);
  assert.deepEqual(supabase.writes, []);
});

const JOBS_SRC = fs.readFileSync(path.join(__dirname, '../../jobs.js'), 'utf8');

test('jobs.js clears failed_permanent only on a deliberate retry', () => {
  assert.match(JOBS_SRC, /clearFailedPermanentStage/);
  assert.match(
    JOBS_SRC,
    /if \(retry === true\) \{\s*await clearFailedPermanentStage/,
    'automatic dispatch must never reopen a stopped stage'
  );

  const clearAt = JOBS_SRC.indexOf('clearFailedPermanentStage');
  const claimAt = JOBS_SRC.indexOf('claimJob({');
  assert.ok(clearAt !== -1 && claimAt !== -1);
  assert.ok(
    clearAt < claimAt,
    'clear the stage before spending money so a concurrent pull sees pending'
  );
});

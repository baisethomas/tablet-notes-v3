const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  clearFailedPermanentStage,
  prepareStageForDeliberateRetry,
  STATUS_FAILED_PERMANENT,
  STATUS_NO_SPEECH,
  STATUS_TOO_SHORT,
  STATUS_COMPLETE,
  CLOSED_NO_RETRY_STAGE_STATUSES
} = require('../sermonStatus');

// TAB-91. Entry into failed_permanent is server-owned. Exit must be too —
// TAB-90 refuses a client push out of any terminal state, which is why the
// old Retry button became a silent no-op after #52.

function fakeSupabase({ selectResult = [{ id: 'sermon-1' }], readStatus = 'pending' } = {}) {
  const writes = [];
  const reads = [];
  return {
    writes,
    reads,
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
        },
        select(columns) {
          const rec = { columns, filters: [] };
          const chain = {
            eq(column, value) {
              rec.filters.push(['eq', column, value]);
              return chain;
            },
            async maybeSingle() {
              reads.push(rec);
              return {
                data: { transcription_status: readStatus, summary_status: readStatus },
                error: null
              };
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

test('a supabase write failure is reported, not swallowed', async () => {
  const writes = [];
  const supabase = {
    from(table) {
      assert.equal(table, 'sermons');
      return {
        update(patch) {
          const chain = {
            eq() {
              return chain;
            },
            async select() {
              writes.push(patch);
              return { data: null, error: { message: 'connection reset' } };
            }
          };
          return chain;
        }
      };
    }
  };

  const result = await clearFailedPermanentStage({
    supabase,
    sermonId: 'sermon-1',
    stage: 'transcription'
  });

  assert.equal(result.applied, false);
  assert.equal(result.error.message, 'connection reset');
  assert.equal(writes.length, 1);
});

test('prepare refuses closed terminals that Retry must not reopen', async () => {
  for (const status of CLOSED_NO_RETRY_STAGE_STATUSES) {
    const result = await prepareStageForDeliberateRetry({
      supabase: fakeSupabase(),
      sermon: { id: 'sermon-1', transcription_status: status },
      stage: 'transcription'
    });
    assert.equal(result.ok, false);
    assert.equal(result.statusCode, 409);
  }
  assert.deepEqual(CLOSED_NO_RETRY_STAGE_STATUSES, [
    STATUS_NO_SPEECH,
    STATUS_TOO_SHORT,
    STATUS_COMPLETE
  ]);
});

test('prepare clears failed_permanent before the job can be revived', async () => {
  const supabase = fakeSupabase();
  const result = await prepareStageForDeliberateRetry({
    supabase,
    sermon: { id: 'sermon-1', transcription_status: STATUS_FAILED_PERMANENT },
    stage: 'transcription',
    now: '2026-08-20T12:00:00.000Z'
  });

  assert.equal(result.ok, true);
  assert.equal(result.cleared, true);
  assert.equal(supabase.writes.length, 1);
});

test('prepare leaves a plain failed/pending stage alone', async () => {
  for (const status of ['failed', 'pending', 'processing']) {
    const supabase = fakeSupabase();
    const result = await prepareStageForDeliberateRetry({
      supabase,
      sermon: { id: 'sermon-1', transcription_status: status },
      stage: 'transcription'
    });
    assert.equal(result.ok, true);
    assert.equal(result.cleared, false);
    assert.deepEqual(supabase.writes, []);
  }
});

test('prepare aborts when clearing failed_permanent errors', async () => {
  const supabase = {
    from() {
      return {
        update() {
          const chain = {
            eq() {
              return chain;
            },
            async select() {
              return { data: null, error: { message: 'connection reset' } };
            }
          };
          return chain;
        }
      };
    }
  };

  const result = await prepareStageForDeliberateRetry({
    supabase,
    sermon: { id: 'sermon-1', transcription_status: STATUS_FAILED_PERMANENT },
    stage: 'transcription'
  });

  assert.equal(result.ok, false);
  assert.equal(result.statusCode, 500);
});

test('prepare re-checks after a clear miss and refuses a still-closed stage', async () => {
  const supabase = fakeSupabase({
    selectResult: [],
    readStatus: STATUS_NO_SPEECH
  });

  const result = await prepareStageForDeliberateRetry({
    supabase,
    sermon: { id: 'sermon-1', transcription_status: STATUS_FAILED_PERMANENT },
    stage: 'transcription'
  });

  assert.equal(result.ok, false);
  assert.equal(result.statusCode, 409);
  assert.equal(supabase.reads.length, 1);
});

const JOBS_SRC = fs.readFileSync(path.join(__dirname, '../../jobs.js'), 'utf8');

test('jobs.js prepares the stage before revive/insert so the reaper cannot race', () => {
  assert.match(JOBS_SRC, /prepareStageForDeliberateRetry/);
  assert.match(
    JOBS_SRC,
    /if \(retry === true\) \{\s*const prepared = await prepareStageForDeliberateRetry/,
    'automatic dispatch must never reopen a stopped stage'
  );
  assert.match(
    JOBS_SRC,
    /if \(!prepared\.ok\)/,
    'a refused or failed prepare must abort before claim/submit'
  );

  const prepareAt = JOBS_SRC.indexOf('prepareStageForDeliberateRetry');
  const reviveAt = JOBS_SRC.indexOf(".in('status', [JOB_STATUS.DEAD, JOB_STATUS.FAILED])");
  const claimAt = JOBS_SRC.indexOf('claimJob({');
  assert.ok(prepareAt !== -1 && reviveAt !== -1 && claimAt !== -1);
  assert.ok(
    prepareAt < reviveAt && reviveAt < claimAt,
    'clear/refuse first, then revive to queued, then claim — never revive first'
  );
});

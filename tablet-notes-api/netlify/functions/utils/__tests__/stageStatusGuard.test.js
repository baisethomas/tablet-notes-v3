const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isForbiddenStageRegression,
  planStageStatusWrites,
  stageNotTerminalPredicate,
  applyStageStatusWrites
} = require('../sermonStatus');

// TAB-90: the server marks a stage complete when a durable job finishes, and a
// client with dirty metadata could push its stale `pending` straight back over
// it. The job is already terminal, so nothing ever corrected it again.
//
// The first attempt compared timestamps — a deliberate change happens after the
// server's write, a stale one before it. Review killed it: markPendingSync
// stamps updatedAt for ANY dirty scope, so a title edit hands the stale status
// a fresh timestamp and walks it straight through. These tests pin the rule
// that replaced it, which involves no clocks at all.

test('a client may not walk a completed stage backwards', () => {
  for (const incomingStatus of ['pending', 'processing', 'failed']) {
    assert.equal(
      isForbiddenStageRegression({ serverStatus: 'complete', incomingStatus }),
      true,
      `"${incomingStatus}" must not undo a completed stage`
    );
  }
});

test('a stage the server has not completed is the client\'s to set', () => {
  for (const serverStatus of ['pending', 'processing', 'failed', null, undefined]) {
    assert.equal(
      isForbiddenStageRegression({ serverStatus, incomingStatus: 'pending' }),
      false,
      `server "${serverStatus}" has no completion to protect`
    );
  }
});

test('complete -> complete is not a regression, and a missing status is untouched', () => {
  assert.equal(isForbiddenStageRegression({ serverStatus: 'complete', incomingStatus: 'complete' }), false);
  assert.equal(isForbiddenStageRegression({ serverStatus: 'complete', incomingStatus: undefined }), false);
  assert.equal(isForbiddenStageRegression({ serverStatus: 'complete', incomingStatus: null }), false);
});

// --- planning -----------------------------------------------------------------

test('the offline-title-edit sequence drops the status and nothing else', () => {
  // The exact shape of the bug: the server finished the transcription, the
  // client edited a title while away and pushed its stale view of both stages.
  const { writes, dropped } = planStageStatusWrites({
    incoming: { transcriptionStatus: 'pending', summaryStatus: 'pending' },
    server: { transcription_status: 'complete', summary_status: 'complete' }
  });

  assert.deepEqual(dropped, ['transcription_status', 'summary_status']);
  assert.deepEqual(writes, [], 'nothing may be written over a completed stage');
});

test('one completed stage does not shield the other', () => {
  const { writes, dropped } = planStageStatusWrites({
    incoming: { transcriptionStatus: 'pending', summaryStatus: 'processing' },
    server: { transcription_status: 'complete', summary_status: 'pending' }
  });

  assert.deepEqual(dropped, ['transcription_status']);
  assert.deepEqual(writes, [{ column: 'summary_status', value: 'processing' }]);
});

test('a status the server already holds produces no write', () => {
  // Keeps the ordinary metadata push to a single statement, and means a stage
  // completing mid-request is left alone rather than restated from a snapshot.
  const { writes, dropped } = planStageStatusWrites({
    incoming: { transcriptionStatus: 'pending', summaryStatus: 'complete' },
    server: { transcription_status: 'pending', summary_status: 'complete' }
  });

  assert.deepEqual(writes, []);
  assert.deepEqual(dropped, []);
});

test('genuine forward progress is written', () => {
  const { writes, dropped } = planStageStatusWrites({
    incoming: { transcriptionStatus: 'complete' },
    server: { transcription_status: 'processing' }
  });

  assert.deepEqual(writes, [{ column: 'transcription_status', value: 'complete' }]);
  assert.deepEqual(dropped, []);
});

test('a push carrying no stage statuses is a no-op', () => {
  assert.deepEqual(
    planStageStatusWrites({ incoming: {}, server: { transcription_status: 'complete' } }),
    { writes: [], dropped: [] }
  );
  assert.deepEqual(planStageStatusWrites(), { writes: [], dropped: [] });
});

// --- the compare-and-set ------------------------------------------------------

test('the predicate matches a null column, not just a non-terminal one', () => {
  // `status <> 'complete'` is NULL — not true — for a row that never had one,
  // so a bare neq would silently match nothing and drop every write.
  // The terminal set itself is pinned in terminalStatus.test.js.
  const p = stageNotTerminalPredicate('transcription_status');
  assert.ok(p.startsWith('transcription_status.is.null,'), 'a never-set column must still be writable');
  assert.ok(p.includes('neq.complete'));
});

/** Records what was asked of it and returns a caller-chosen result. */
function fakeSupabase(result) {
  const calls = [];
  let current;
  const chain = {
    update(patch) { current.patch = patch; return chain; },
    eq(column, value) { current.filters.push(['eq', column, value]); return chain; },
    or(expr) { current.filters.push(['or', expr]); return chain; },
    select() { return Promise.resolve(result(current)); }
  };
  return {
    calls,
    from(table) {
      current = { table, filters: [] };
      calls.push(current);
      return chain;
    }
  };
}

test('a stage write is scoped to the owner and refuses to overwrite complete', async () => {
  const supabase = fakeSupabase(() => ({ data: [{ id: 'sermon-1' }], error: null }));

  const { dropped } = await applyStageStatusWrites({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    writes: [{ column: 'transcription_status', value: 'pending' }]
  });

  assert.deepEqual(dropped, []);
  assert.equal(supabase.calls.length, 1);
  const [call] = supabase.calls;
  assert.equal(call.table, 'sermons');
  assert.deepEqual(call.patch, { transcription_status: 'pending' });
  assert.deepEqual(call.filters, [
    ['eq', 'id', 'sermon-1'],
    ['eq', 'user_id', 'user-1'],
    ['or', stageNotTerminalPredicate('transcription_status')]
  ]);
});

test('the write does not carry a timestamp — the metadata update owns that', () => {
  // Stamping updated_at here would let a stage write echo the client's clock
  // back before the caller knows whether anything was dropped.
  const supabase = fakeSupabase(() => ({ data: [{ id: 'sermon-1' }], error: null }));
  return applyStageStatusWrites({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    writes: [{ column: 'summary_status', value: 'processing' }]
  }).then(() => {
    assert.deepEqual(Object.keys(supabase.calls[0].patch), ['summary_status']);
  });
});

test('a stage that completes mid-request keeps the server value', async () => {
  // Zero rows matched: the compare-and-set refused the write because the job
  // finished between the caller's read and this write.
  const supabase = fakeSupabase(() => ({ data: [], error: null }));

  const { dropped } = await applyStageStatusWrites({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    writes: [{ column: 'transcription_status', value: 'pending' }]
  });

  assert.deepEqual(dropped, ['transcription_status'], 'the caller must know to bump the row');
});

test('a failed write is not reported as a drop', async () => {
  // A transport failure says nothing about which value is newer; treating it as
  // a drop would bump the timestamp on a row that never changed.
  const supabase = fakeSupabase(() => ({ data: null, error: { message: 'boom' } }));
  const warnings = [];

  const { dropped } = await applyStageStatusWrites({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    writes: [{ column: 'transcription_status', value: 'pending' }],
    logger: { warn: (msg, ctx) => warnings.push([msg, ctx]) }
  });

  assert.deepEqual(dropped, []);
  assert.equal(warnings.length, 1);
});

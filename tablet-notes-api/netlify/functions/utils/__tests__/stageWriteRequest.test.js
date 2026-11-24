const test = require('node:test');
const assert = require('node:assert/strict');
const { createClient } = require('@supabase/supabase-js');

const {
  TERMINAL_STATUSES,
  applySermonStageTerminal,
  applyStageStatusWrites,
  updateWhileStageNotTerminal
} = require('../sermonStatus');

// TAB-141. Every guarded stage write was rejected in production with
// "column sermons.transcription_status does not exist" and wrote nothing. The
// tests that covered the guard asserted on calls to a hand-written fake client,
// so they passed while the real request was one PostgREST refuses.
//
// These tests run the REAL Supabase client and stop only at the network. The
// stand-in below receives the actual HTTP request and applies the one PostgREST
// rule that mattered: on an update, an `or`/`and` filter is evaluated a second
// time against the returned rows, which carry only the selected columns.

const silent = { info() {}, warn() {}, error() {} };
const SERMON_ID = '11111111-1111-4111-8111-111111111111';
const USER_ID = '22222222-2222-4222-8222-222222222222';

function matches(row, column, expression) {
  if (expression.startsWith('eq.')) return String(row[column]) === expression.slice(3);
  if (expression === 'is.null') return row[column] === null || row[column] === undefined;
  if (expression.startsWith('not.in.(') && expression.endsWith(')')) {
    // SQL semantics: NULL NOT IN (...) is NULL, which does not match.
    if (row[column] === null || row[column] === undefined) return false;
    return !expression.slice('not.in.('.length, -1).split(',').includes(row[column]);
  }
  throw new Error(`stand-in PostgREST does not model the filter ${column}=${expression}`);
}

/** A one-table PostgREST: just enough to answer a PATCH on `sermons`. */
function fakePostgrest(rows) {
  const requests = [];

  const fetch = async (input, init = {}) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    const method = init.method || 'GET';
    const params = [...url.searchParams.entries()];
    requests.push({ method, path: url.pathname, params });

    const json = (status, body) => new Response(JSON.stringify(body), {
      status,
      headers: { 'content-type': 'application/json' }
    });

    if (method !== 'PATCH' || url.pathname !== '/rest/v1/sermons') {
      return json(404, { message: 'not modelled' });
    }

    const selected = (url.searchParams.get('select') || '*').split(',');
    for (const [key, value] of params) {
      if (key !== 'or' && key !== 'and') continue;
      // The logic filter runs again over the returned rows. Any column it
      // names that was not selected does not exist there.
      const missing = ['transcription_status', 'summary_status']
        .find((column) => value.includes(column) && !selected.includes(column) && !selected.includes('*'));
      if (missing) {
        return json(400, { code: '42703', message: `column sermons.${missing} does not exist` });
      }
    }

    const filters = params.filter(([key]) => !['select', 'or', 'and', 'columns'].includes(key));
    const patch = JSON.parse(init.body);
    const updated = rows.filter((row) => filters.every(([column, expression]) => matches(row, column, expression)));
    for (const row of updated) Object.assign(row, patch);
    return json(200, updated.map((row) => Object.fromEntries(selected.map((column) => [column, row[column]]))));
  };

  const supabase = createClient('https://stand-in.supabase.co', 'test-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch }
  });
  return { supabase, requests, rows };
}

const sermon = (overrides = {}) => ({
  id: SERMON_ID,
  user_id: USER_ID,
  transcription_status: 'processing',
  summary_status: 'pending',
  ...overrides
});

test('the stand-in rejects the request production rejected', async () => {
  // Pins the reason this file exists: the old call shape, sent through the real
  // client, fails exactly as it did in production on 2026-11-23.
  const { supabase, rows } = fakePostgrest([sermon()]);

  const { data, error } = await supabase
    .from('sermons')
    .update({ transcription_status: 'complete' })
    .eq('id', SERMON_ID)
    .or('transcription_status.is.null,and(transcription_status.neq.complete)')
    .select('id');

  assert.equal(data, null);
  assert.equal(error.code, '42703');
  assert.match(error.message, /column sermons\.transcription_status does not exist/);
  assert.equal(rows[0].transcription_status, 'processing', 'and nothing was written');
});

test('a guarded stage write lands on a stage that has not stopped', async () => {
  const { supabase, requests, rows } = fakePostgrest([sermon()]);

  const result = await applySermonStageTerminal({
    supabase,
    sermonId: SERMON_ID,
    stage: 'transcription',
    status: 'complete',
    onlyIfNotTerminal: true,
    logger: silent
  });

  assert.equal(result.error, null);
  assert.equal(result.applied, true);
  assert.equal(rows[0].transcription_status, 'complete');

  assert.equal(requests.length, 1);
  const [request] = requests;
  assert.equal(request.method, 'PATCH');
  assert.deepEqual(request.params, [
    ['id', `eq.${SERMON_ID}`],
    ['transcription_status', 'not.in.(complete,no_speech,failed_permanent,too_short)'],
    ['select', 'id']
  ]);
});

test('no guarded stage write sends an or/and filter', async () => {
  // The whole bug in one assertion, for both callers and both columns.
  const { supabase, requests } = fakePostgrest([sermon({ transcription_status: null, summary_status: null })]);

  await applySermonStageTerminal({
    supabase, sermonId: SERMON_ID, stage: 'summary', status: 'too_short', onlyIfNotTerminal: true, logger: silent
  });
  await applyStageStatusWrites({
    supabase,
    sermonId: SERMON_ID,
    userId: USER_ID,
    writes: [{ column: 'transcription_status', value: 'pending' }],
    logger: silent
  });

  assert.ok(requests.length >= 2);
  for (const request of requests) {
    const keys = request.params.map(([key]) => key);
    assert.ok(!keys.includes('or') && !keys.includes('and'), `logic filter sent: ${JSON.stringify(request.params)}`);
  }
});

test('a guarded stage write leaves every terminal state alone', async () => {
  for (const terminal of TERMINAL_STATUSES) {
    const { supabase, rows } = fakePostgrest([sermon({ summary_status: terminal })]);

    const result = await applySermonStageTerminal({
      supabase,
      sermonId: SERMON_ID,
      stage: 'summary',
      status: 'failed_permanent',
      onlyIfNotTerminal: true,
      logger: silent
    });

    assert.equal(result.error, null, terminal);
    assert.equal(result.applied, false, `${terminal} must not be overwritten`);
    assert.equal(rows[0].summary_status, terminal);
  }
});

test('a stage that was never set still takes the write', async () => {
  // NOT IN is NULL for a null column, so the first request matches nothing and
  // the second, `is.null`, is what lands.
  const { supabase, requests, rows } = fakePostgrest([sermon({ transcription_status: null })]);

  const result = await applySermonStageTerminal({
    supabase,
    sermonId: SERMON_ID,
    stage: 'transcription',
    status: 'failed_permanent',
    onlyIfNotTerminal: true,
    logger: silent
  });

  assert.equal(result.applied, true);
  assert.equal(rows[0].transcription_status, 'failed_permanent');
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[1].params, [
    ['id', `eq.${SERMON_ID}`],
    ['transcription_status', 'is.null'],
    ['select', 'id']
  ]);
});

test('writing a terminal status still reports that it landed', async () => {
  // The trap in the obvious fix. Had the guard been kept as an `or` filter with
  // the column added to `select`, it would be tested against the NEW value:
  // the row would change and the caller would be told it had not.
  const { supabase, rows } = fakePostgrest([sermon({ summary_status: 'processing' })]);

  const result = await updateWhileStageNotTerminal({
    supabase,
    patch: { summary_status: 'too_short' },
    column: 'summary_status',
    scope: { id: SERMON_ID }
  });

  assert.deepEqual(result, { applied: true, error: null });
  assert.equal(rows[0].summary_status, 'too_short');
});

test('a client stage push is scoped to its owner and cannot undo a finished stage', async () => {
  const { supabase, requests, rows } = fakePostgrest([sermon({ transcription_status: 'complete' })]);

  const { dropped } = await applyStageStatusWrites({
    supabase,
    sermonId: SERMON_ID,
    userId: USER_ID,
    writes: [
      { column: 'transcription_status', value: 'pending' },
      { column: 'summary_status', value: 'processing' }
    ],
    logger: silent
  });

  assert.deepEqual(dropped, ['transcription_status'], 'the stale pending is dropped');
  assert.equal(rows[0].transcription_status, 'complete');
  assert.equal(rows[0].summary_status, 'processing', 'the live stage is written');
  for (const request of requests) {
    assert.ok(
      request.params.some(([key, value]) => key === 'user_id' && value === `eq.${USER_ID}`),
      'every request carries the owner'
    );
  }
});

test('a push for someone else\'s sermon writes nothing', async () => {
  const { supabase, rows } = fakePostgrest([sermon({ user_id: '33333333-3333-4333-8333-333333333333' })]);

  const { dropped } = await applyStageStatusWrites({
    supabase,
    sermonId: SERMON_ID,
    userId: USER_ID,
    writes: [{ column: 'transcription_status', value: 'failed' }],
    logger: silent
  });

  assert.deepEqual(dropped, ['transcription_status']);
  assert.equal(rows[0].transcription_status, 'processing');
});

test('a database error is returned, not reported as "already terminal"', async () => {
  const supabase = createClient('https://stand-in.supabase.co', 'test-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async () => new Response(JSON.stringify({ code: '57014', message: 'statement timeout' }), {
        status: 500,
        headers: { 'content-type': 'application/json' }
      })
    }
  });

  const result = await updateWhileStageNotTerminal({
    supabase,
    patch: { summary_status: 'too_short' },
    column: 'summary_status',
    scope: { id: SERMON_ID }
  });

  assert.equal(result.applied, false);
  assert.equal(result.error.message, 'statement timeout');
});

test('a guarded write with no scope is refused before any request is sent', async () => {
  // Without a scope the update would hit every sermon whose stage has not
  // stopped. Two sermons, two owners: neither may change.
  for (const scope of [undefined, null, {}]) {
    const { supabase, requests, rows } = fakePostgrest([
      sermon(),
      sermon({ id: '33333333-3333-4333-8333-333333333333', user_id: '44444444-4444-4444-8444-444444444444' })
    ]);

    await assert.rejects(
      updateWhileStageNotTerminal({
        supabase,
        patch: { transcription_status: 'complete' },
        column: 'transcription_status',
        scope
      }),
      /requires a non-empty scope/
    );

    assert.equal(requests.length, 0, 'no request left the client');
    assert.deepEqual(rows.map((row) => row.transcription_status), ['processing', 'processing']);
  }
});

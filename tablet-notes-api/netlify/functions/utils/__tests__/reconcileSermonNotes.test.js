const test = require('node:test');
const assert = require('node:assert/strict');
const { reconcileSermonNotes } = require('../reconcileSermonNotes');

const silentLogger = { info() {}, warn() {}, error() {} };

// Minimal chainable stand-in for the supabase-js query builder, scoped to the
// notes table. Each awaited chain records its operation and applies it to an
// in-memory row set so tests can assert on ORDER of writes and on the rows
// that survive a failure.
function fakeNotesTable({ existing = [], fail = {} } = {}) {
  const ops = [];
  let rows = existing.map(r => ({ ...r }));
  let nextId = 100;

  function execute(b) {
    ops.push(b.op);
    if (fail[b.op]) {
      return { data: null, error: { message: `${b.op} failed`, code: '23502' } };
    }
    switch (b.op) {
      case 'select':
        return { data: rows.filter(r => r.sermon_id === b.filters.sermon_id), error: null };
      case 'insert': {
        const inserted = b.payload.map(r => ({ ...r, id: `id-${nextId++}` }));
        rows.push(...inserted);
        return { data: inserted, error: null };
      }
      case 'update':
        rows = rows.map(r => (r.id === b.filters.id ? { ...r, ...b.payload } : r));
        return { data: null, error: null };
      case 'delete':
        rows = rows.filter(r => !b.filters.id_in.includes(r.id));
        return { data: null, error: null };
      default:
        throw new Error(`unexpected op ${b.op}`);
    }
  }

  function builder() {
    const b = {
      op: null,
      payload: null,
      filters: {},
      select() { if (!b.op) b.op = 'select'; return b; },
      insert(r) { b.op = 'insert'; b.payload = r; return b; },
      update(r) { b.op = 'update'; b.payload = r; return b; },
      delete() { b.op = 'delete'; return b; },
      eq(k, v) { b.filters[k] = v; return b; },
      in(k, v) { b.filters[`${k}_in`] = v; return b; },
      then(resolve, reject) { return Promise.resolve().then(() => execute(b)).then(resolve, reject); }
    };
    return b;
  }

  return {
    ops,
    get rows() { return rows; },
    from(table) {
      assert.equal(table, 'notes');
      return builder();
    }
  };
}

const existingNotes = [
  { id: 'row-a', local_id: 'a', sermon_id: 'sermon-1', user_id: 'user-1', text: 'A old', timestamp: 5 },
  { id: 'row-b', local_id: 'b', sermon_id: 'sermon-1', user_id: 'user-1', text: 'B', timestamp: 9 }
];

test('updates matches, inserts new, and deletes stale rows LAST', async () => {
  const supabase = fakeNotesTable({ existing: existingNotes });

  const ok = await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [
      { id: 'a', text: 'A new', timestamp: 5.4 },
      { id: 'c', text: 'C', timestamp: 20 }
    ],
    logger: silentLogger
  });

  assert.equal(ok, true);
  assert.deepEqual(supabase.ops, ['select', 'insert', 'update', 'delete']);
  const byLocal = Object.fromEntries(supabase.rows.map(r => [r.local_id, r]));
  assert.equal(byLocal.a.text, 'A new');
  assert.equal(byLocal.a.id, 'row-a', 'matched row keeps its remote id');
  assert.equal(byLocal.c.text, 'C');
  assert.equal(byLocal.c.user_id, 'user-1');
  assert.equal(byLocal.b, undefined, 'note missing from the payload is removed');
});

test('a failed insert leaves every existing note intact and is not acknowledged', async () => {
  const supabase = fakeNotesTable({ existing: existingNotes, fail: { insert: true } });

  const ok = await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [{ id: 'c', text: 'C', timestamp: 20 }],
    logger: silentLogger
  });

  assert.equal(ok, false);
  assert.ok(!supabase.ops.includes('delete'), 'nothing is deleted after a failed insert');
  assert.deepEqual(supabase.rows.map(r => r.local_id).sort(), ['a', 'b']);
});

test('a failed read makes no writes at all', async () => {
  const supabase = fakeNotesTable({ existing: existingNotes, fail: { select: true } });

  const ok = await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [{ id: 'c', text: 'C', timestamp: 20 }],
    logger: silentLogger
  });

  assert.equal(ok, false);
  assert.deepEqual(supabase.ops, ['select']);
  assert.equal(supabase.rows.length, 2);
});

test('a failed delete keeps the inserts and updates but is not acknowledged', async () => {
  const supabase = fakeNotesTable({ existing: existingNotes, fail: { delete: true } });

  const ok = await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [{ id: 'c', text: 'C', timestamp: 20 }],
    logger: silentLogger
  });

  assert.equal(ok, false);
  assert.deepEqual(supabase.rows.map(r => r.local_id).sort(), ['a', 'b', 'c']);
});

test('an empty payload removes every note (user deleted them all)', async () => {
  const supabase = fakeNotesTable({ existing: existingNotes });

  const ok = await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [],
    logger: silentLogger
  });

  assert.equal(ok, true);
  assert.deepEqual(supabase.ops, ['select', 'delete']);
  assert.equal(supabase.rows.length, 0);
});

test('unchanged notes are neither rewritten nor deleted', async () => {
  const supabase = fakeNotesTable({ existing: existingNotes });

  const ok = await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [
      { id: 'a', text: 'A old', timestamp: 5 },
      { id: 'b', text: 'B', timestamp: 9.2 }
    ],
    logger: silentLogger
  });

  assert.equal(ok, true);
  assert.deepEqual(supabase.ops, ['select']);
});

test('rounds fractional timestamps for the integer column', async () => {
  const supabase = fakeNotesTable();

  await reconcileSermonNotes({
    supabase,
    sermonId: 'sermon-1',
    userId: 'user-1',
    notes: [{ id: 'x', text: 'X', timestamp: 10.6 }],
    logger: silentLogger
  });

  assert.equal(supabase.rows[0].timestamp, 11);
});

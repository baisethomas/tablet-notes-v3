const test = require('node:test');
const assert = require('node:assert/strict');
const { createSermonChildren } = require('../createSermonChildren');

const silentLogger = { info() {}, warn() {}, error() {} };

function fakeSupabase(failingTables = []) {
  const calls = [];
  return {
    calls,
    from(table) {
      return {
        insert(rows) {
          return {
            async select() {
              calls.push({ table, rows });
              if (failingTables.includes(table)) {
                return { data: null, error: { message: `${table} insert failed`, code: '23502' } };
              }
              return { data: Array.isArray(rows) ? rows : [rows], error: null };
            }
          };
        }
      };
    }
  };
}

const fullBody = {
  notes: [{ id: 'note-local-1', text: 'A note', timestamp: 12 }],
  transcript: { id: 'transcript-local-1', text: 'Transcript text' },
  summary: { id: 'summary-local-1', title: 'Title', text: 'Summary text', type: 'devotional', status: 'complete' }
};

test('acknowledges all scopes when every child insert succeeds', async () => {
  const supabase = fakeSupabase();

  const scopes = await createSermonChildren({
    supabase,
    body: fullBody,
    sermonId: 'sermon-1',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.deepEqual(scopes, { metadata: true, notes: true, transcript: true, summary: true });
  assert.deepEqual(supabase.calls.map(c => c.table), ['notes', 'transcripts', 'summaries']);
});

test('reports a failed child scope instead of acknowledging it', async () => {
  const supabase = fakeSupabase(['transcripts']);

  const scopes = await createSermonChildren({
    supabase,
    body: fullBody,
    sermonId: 'sermon-1',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.deepEqual(scopes, { metadata: true, notes: true, transcript: false, summary: true });
});

test('a failed scope does not block the remaining child inserts', async () => {
  const supabase = fakeSupabase(['notes']);

  const scopes = await createSermonChildren({
    supabase,
    body: fullBody,
    sermonId: 'sermon-1',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.deepEqual(scopes, { metadata: true, notes: false, transcript: true, summary: true });
  assert.deepEqual(supabase.calls.map(c => c.table), ['notes', 'transcripts', 'summaries']);
});

test('rounds fractional note timestamps for the integer column', async () => {
  const supabase = fakeSupabase();

  await createSermonChildren({
    supabase,
    body: {
      notes: [
        { id: 'note-local-1', text: 'A note', timestamp: 12.483749 },
        { id: 'note-local-2', text: 'Another', timestamp: 754.9 },
        { id: 'note-local-3', text: 'No timestamp' }
      ]
    },
    sermonId: 'sermon-1',
    userId: 'user-1',
    logger: silentLogger
  });

  const noteRows = supabase.calls.find(c => c.table === 'notes').rows;
  assert.deepEqual(noteRows.map(r => r.timestamp), [12, 755, 0]);
  assert.ok(noteRows.every(r => Number.isInteger(r.timestamp)));
});

test('acknowledges scopes vacuously when there is nothing to insert', async () => {
  const supabase = fakeSupabase(['notes', 'transcripts', 'summaries']);

  const scopes = await createSermonChildren({
    supabase,
    body: { notes: [], transcript: { text: '' }, summary: null },
    sermonId: 'sermon-1',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.deepEqual(scopes, { metadata: true, notes: true, transcript: true, summary: true });
  assert.equal(supabase.calls.length, 0);
});

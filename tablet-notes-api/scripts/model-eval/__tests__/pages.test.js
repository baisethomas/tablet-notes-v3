'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { allRows } = require('../lib/pages');

// A stand-in PostgREST that never returns more than `cap` rows per request,
// whatever limit is asked for.
function server(total, cap) {
  const calls = [];
  const get = async (q) => {
    calls.push(q);
    const p = new URLSearchParams(q.split('?')[1]);
    const offset = Number(p.get('offset')), limit = Math.min(Number(p.get('limit')), cap);
    return Array.from({ length: Math.max(0, Math.min(limit, total - offset)) }, (_, i) => ({ id: offset + i }));
  };
  return { get, calls };
}

test('every row is read when the result is larger than one page', async () => {
  const s = server(2500, 1000);
  const rows = await allRows(s.get, 'transcripts?select=id');
  assert.equal(rows.length, 2500);
  assert.equal(new Set(rows.map(r => r.id)).size, 2500);
  assert.match(s.calls[0], /^transcripts\?select=id&order=id&limit=1000&offset=0$/);
});

test('a server that caps pages below the size asked for is still read to the end', async () => {
  const s = server(950, 100);
  assert.equal((await allRows(s.get, 't?select=id', { pageSize: 1000 })).length, 950);
});

test('a small or empty result needs no special case', async () => {
  assert.equal((await allRows(server(3, 1000).get, 't?select=id')).length, 3);
  assert.deepEqual(await allRows(server(0, 1000).get, 't?select=id'), []);
});

test('a reply that is not a list of rows, or never ends, is an error', async () => {
  await assert.rejects(allRows(async () => ({ message: 'nope' }), 't?select=id'), /expected a JSON array/);
  await assert.rejects(allRows(async () => [{ id: 1 }], 't?select=id', { maxPages: 5 }), /more than 5 pages/);
});

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { snapshotInputs, loadInputs, hasInputs, assertRunName } = require('../lib/inputs');

function write(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data));
}

// What `pull` leaves in data/.
function writePull(dataDir, transcripts) {
  fs.rmSync(path.join(dataDir, 'transcripts'), { recursive: true, force: true });
  for (const t of transcripts) write(path.join(dataDir, 'transcripts', `${t.id}.json`), { id: t.id, text: t.text });
  write(path.join(dataDir, 'manifest.json'), transcripts.map((t, i) => ({ id: t.id, serviceType: 'Sermon', tier: i % 2 === 0 ? 'premium' : 'basic' })));
}

function dirs() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'model-eval-inputs-'));
  return { data: path.join(root, 'data'), run: path.join(root, 'runs', 'r1') };
}

test('a run keeps the transcripts it started with after a new pull', () => {
  const { data, run } = dirs();
  writePull(data, [{ id: 'a', text: 'first sermon' }, { id: 'b', text: 'second sermon' }]);
  const first = snapshotInputs(data, run);
  assert.deepEqual(first.map(t => [t.id, t.text, t.tier]), [['a', 'first sermon', 'premium'], ['b', 'second sermon', 'basic']]);

  // A later pull: one id reused with different text, one dropped, one new.
  writePull(data, [{ id: 'a', text: 'a different recording' }, { id: 'c', text: 'third sermon' }]);
  assert.deepEqual(loadInputs(run).map(t => [t.id, t.text]), [['a', 'first sermon'], ['b', 'second sermon']]);
  // Resuming the run does not re-copy either.
  assert.deepEqual(snapshotInputs(data, run).map(t => [t.id, t.text]), [['a', 'first sermon'], ['b', 'second sermon']]);
});

test('a run survives data/ being removed entirely', () => {
  const { data, run } = dirs();
  writePull(data, [{ id: 'a', text: 'first sermon' }]);
  snapshotInputs(data, run);
  fs.rmSync(data, { recursive: true });
  assert.equal(loadInputs(run)[0].text, 'first sermon');
});

test('a run with no snapshot is refused instead of reading data/', () => {
  const { data, run } = dirs();
  writePull(data, [{ id: 'a', text: 'first sermon' }]);
  fs.mkdirSync(run, { recursive: true });
  assert.equal(hasInputs(run), false);
  assert.throws(() => loadInputs(run), /no input snapshot/);
});

test('a snapshot whose text was changed is refused', () => {
  const { data, run } = dirs();
  writePull(data, [{ id: 'a', text: 'first sermon' }]);
  snapshotInputs(data, run);
  const f = path.join(run, 'inputs', 'transcripts', 'a.json');
  const t = JSON.parse(fs.readFileSync(f, 'utf8'));
  t.text = 'edited afterwards';
  fs.writeFileSync(f, JSON.stringify(t));
  assert.throws(() => loadInputs(run), /does not match its recorded hash/);
});

test('a copy interrupted before its manifest was written is not a snapshot', () => {
  const { data, run } = dirs();
  writePull(data, [{ id: 'a', text: 'first sermon' }]);
  write(path.join(run, 'inputs', 'transcripts', 'a.json'), { id: 'a', text: 'partial' });
  assert.equal(hasInputs(run), false);
  assert.equal(snapshotInputs(data, run)[0].text, 'first sermon');
});

test('a run name must be one plain path segment', () => {
  for (const ok of ['2026-11-23-confirm', 'smoke', 'run_2.v1']) assert.equal(assertRunName(ok), ok);
  for (const bad of ['..', '.', '../..', '../outside', 'a/b', 'a\\b', '/tmp/x', '', ' ', 'run name', true, undefined]) {
    assert.throws(() => assertRunName(bad), /invalid --run name/, String(bad));
  }
});

test('a planned run whose inputs are gone is refused, not given a fresh copy of data/', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'model-eval-planned-'));
  const data = path.join(root, 'data'), run = path.join(root, 'runs', 'r1');
  fs.mkdirSync(path.join(data, 'transcripts'), { recursive: true });
  fs.writeFileSync(path.join(data, 'transcripts', 'a.json'), JSON.stringify({ id: 'a', text: 'first pull' }));
  fs.writeFileSync(path.join(data, 'manifest.json'), JSON.stringify([{ id: 'a', tier: 'premium' }]));
  // First invocation: no plan yet, so the pull is copied.
  assert.equal(snapshotInputs(data, run).length, 1);
  // A later invocation of the same run reads its own copy, planned or not.
  assert.equal(snapshotInputs(data, run, { planned: true })[0].text, 'first pull');
  // Inputs removed after the run was planned: nothing is written in their place.
  fs.rmSync(path.join(run, 'inputs'), { recursive: true });
  assert.throws(() => snapshotInputs(data, run, { planned: true }), /has a plan but its input snapshot .* is missing/);
  assert.equal(hasInputs(run), false);
  assert.equal(fs.existsSync(path.join(run, 'inputs')), false);
});

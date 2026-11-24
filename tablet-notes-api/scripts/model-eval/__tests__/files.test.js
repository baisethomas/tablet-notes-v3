'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { readJsonOrNull, writeJson, listDir } = require('../lib/files');

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'model-eval-files-'));

test('a written file reads back and leaves no temporary file behind', () => {
  const dir = tmp();
  const f = path.join(dir, 'a', 'b', 'x.json');
  writeJson(f, { n: 1 });
  writeJson(f, { n: 2 });
  assert.deepEqual(readJsonOrNull(f), { n: 2 });
  assert.deepEqual(fs.readdirSync(path.dirname(f)), ['x.json']);
});

test('a write that fails leaves the previous file whole', () => {
  const dir = tmp();
  const f = path.join(dir, 'x.json');
  writeJson(f, { n: 1 });
  const circular = {}; circular.self = circular;
  assert.throws(() => writeJson(f, circular));
  // A failure while the bytes are being written: the rename never happens.
  const realWrite = fs.writeFileSync;
  fs.writeFileSync = (file, text) => { realWrite(file, String(text).slice(0, 3)); throw new Error('ENOSPC'); };
  try { assert.throws(() => writeJson(f, { n: 2 }), /ENOSPC/); } finally { fs.writeFileSync = realWrite; }
  assert.deepEqual(readJsonOrNull(f), { n: 1 });
  assert.deepEqual(fs.readdirSync(dir), ['x.json']);
});

test('an absent or unparseable file reads as null', () => {
  const dir = tmp();
  assert.equal(readJsonOrNull(path.join(dir, 'missing.json')), null);
  for (const text of ['', '{"model":"x","result":{"cont', 'not json']) {
    const f = path.join(dir, 'bad.json');
    fs.writeFileSync(f, text);
    assert.equal(readJsonOrNull(f), null, text);
  }
});

test('a read error other than a missing file is not swallowed', () => {
  assert.throws(() => readJsonOrNull(tmp()), /EISDIR/);
});

test('a folder that does not exist lists as empty', () => {
  const dir = tmp();
  assert.deepEqual(listDir(path.join(dir, 'gen')), []);
  writeJson(path.join(dir, 'gen', 'model', 'x.json'), {});
  assert.deepEqual(listDir(path.join(dir, 'gen')), ['model']);
});

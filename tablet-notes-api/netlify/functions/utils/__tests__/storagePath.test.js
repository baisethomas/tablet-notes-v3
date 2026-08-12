const test = require('node:test');
const assert = require('node:assert');

const { buildAudioObjectPath, isUuid, safeExtension } = require('../storagePath');

const USER = '94771a20-c9e7-4a85-ad3d-b8ac29a23501';
const SERMON = '3ffcc32e-4bac-46fe-b30f-77b623c1b7bd';

test('a sermon id yields a stable path — the same one every attempt', () => {
  const a = buildAudioObjectPath({ userId: USER, sermonLocalId: SERMON, fileName: 'sermon_X.m4a' });
  const b = buildAudioObjectPath({ userId: USER, sermonLocalId: SERMON, fileName: 'sermon_X.m4a' });

  assert.strictEqual(a.path, `${USER}/${SERMON}.m4a`);
  assert.strictEqual(a.path, b.path, 'retries must address the same object');
  assert.strictEqual(a.stable, true);
});

test('no sermon id falls back to a random path, and is not upsertable', () => {
  // Already-shipped clients do not send sermonLocalId and must keep working.
  const a = buildAudioObjectPath({ userId: USER, fileName: 'sermon_X.m4a' });
  const b = buildAudioObjectPath({ userId: USER, fileName: 'sermon_X.m4a' });

  assert.notStrictEqual(a.path, b.path, 'legacy behaviour: a fresh path each call');
  assert.strictEqual(a.stable, false, 'a random path must never upsert');
  assert.ok(a.path.startsWith(`${USER}/`));
});

test('a non-UUID sermon id is refused rather than sanitized into the path', () => {
  for (const evil of ['../../etc/passwd', 'not-a-uuid', '', null, undefined, 42, {}]) {
    const r = buildAudioObjectPath({ userId: USER, sermonLocalId: evil, fileName: 'a.m4a' });
    assert.strictEqual(r.stable, false, `${JSON.stringify(evil)} must not produce a stable path`);
    assert.ok(!r.path.includes('..'), 'no traversal may reach the path');
    assert.strictEqual(r.path.split('/').length, 2, 'path stays exactly user/file');
  }
});

test('the extension is constrained, never taken verbatim', () => {
  assert.strictEqual(safeExtension('a.m4a'), 'm4a');
  assert.strictEqual(safeExtension('a.M4A'), 'm4a', 'case-normalised');
  assert.strictEqual(safeExtension('noextension'), 'm4a', 'defaults');
  assert.strictEqual(safeExtension('a.../etc'), 'm4a', 'rejects path characters');
  assert.strictEqual(safeExtension('a.verylongextension'), 'm4a', 'rejects absurd length');
});

test('a userId is required — a path must never begin at the bucket root', () => {
  assert.throws(() => buildAudioObjectPath({ sermonLocalId: SERMON, fileName: 'a.m4a' }));
});

test('isUuid accepts real uuids and rejects near-misses', () => {
  assert.ok(isUuid(SERMON));
  assert.ok(isUuid(SERMON.toUpperCase()));
  assert.ok(!isUuid(SERMON.slice(0, -1)));
  assert.ok(!isUuid(`${SERMON} `));
  assert.ok(!isUuid(`${SERMON}/../x`));
});

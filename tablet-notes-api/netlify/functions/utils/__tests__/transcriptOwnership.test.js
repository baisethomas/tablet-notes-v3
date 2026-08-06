const test = require('node:test');
const assert = require('node:assert/strict');

// No Upstash env in tests: the module uses its per-container in-memory store.
const {
  recordTranscriptOwner,
  getTranscriptOwner,
  _memoryOwners
} = require('../transcriptOwnership');

test.beforeEach(() => {
  _memoryOwners.clear();
});

test('records and returns the owner of a transcript', async () => {
  assert.equal(await recordTranscriptOwner('t-1', 'user-a'), true);
  assert.equal(await getTranscriptOwner('t-1'), 'user-a');
});

test('returns null for an unknown transcript', async () => {
  assert.equal(await getTranscriptOwner('never-recorded'), null);
});

test('returns null (not a throw) for missing arguments', async () => {
  assert.equal(await recordTranscriptOwner(null, 'user-a'), false);
  assert.equal(await recordTranscriptOwner('t-1', null), false);
  assert.equal(await getTranscriptOwner(null), null);
});

test('expired in-memory mappings are treated as unknown', async () => {
  await recordTranscriptOwner('t-old', 'user-a');
  const entry = _memoryOwners.get('transcript_owner:t-old');
  entry.expiresAt = Date.now() - 1;
  assert.equal(await getTranscriptOwner('t-old'), null);
});

test('a different caller sees the recorded owner, enabling a mismatch deny', async () => {
  await recordTranscriptOwner('t-2', 'user-a');
  const owner = await getTranscriptOwner('t-2');
  assert.notEqual(owner, 'user-b');
  assert.equal(owner, 'user-a');
});

const test = require('node:test');
const assert = require('node:assert/strict');

// No Upstash env in tests: the module uses its per-container in-memory store,
// so isDurableOwnershipStore() is false here.
const {
  recordTranscriptOwner,
  lookupTranscriptOwnership,
  isDurableOwnershipStore,
  OWNERSHIP,
  _memoryOwners
} = require('../transcriptOwnership');

test.beforeEach(() => {
  _memoryOwners.clear();
});

test('records and returns the owner of a transcript', async () => {
  assert.equal(await recordTranscriptOwner('t-1', 'user-a'), true);
  assert.deepEqual(await lookupTranscriptOwnership('t-1'), {
    status: OWNERSHIP.OWNED,
    owner: 'user-a'
  });
});

test('an unrecorded transcript is UNKNOWN, not an error', async () => {
  assert.deepEqual(await lookupTranscriptOwnership('never-recorded'), {
    status: OWNERSHIP.UNKNOWN
  });
});

test('missing arguments never throw', async () => {
  assert.equal(await recordTranscriptOwner(null, 'user-a'), false);
  assert.equal(await recordTranscriptOwner('t-1', null), false);
  assert.deepEqual(await lookupTranscriptOwnership(null), { status: OWNERSHIP.UNKNOWN });
});

test('expired in-memory mappings become UNKNOWN', async () => {
  await recordTranscriptOwner('t-old', 'user-a');
  const entry = _memoryOwners.get('transcript_owner:t-old');
  entry.expiresAt = Date.now() - 1;
  assert.deepEqual(await lookupTranscriptOwnership('t-old'), {
    status: OWNERSHIP.UNKNOWN
  });
});

test('a mismatched owner is reported so the caller can hard-deny', async () => {
  await recordTranscriptOwner('t-2', 'user-a');
  const result = await lookupTranscriptOwnership('t-2');
  assert.equal(result.status, OWNERSHIP.OWNED);
  assert.notEqual(result.owner, 'user-b');
});

test('without Redis env the store reports itself non-durable', () => {
  // The transcribe-status handler keys its fail-open/fail-closed decision on
  // this: UNKNOWN denies only when the store is durable (Redis-backed).
  assert.equal(isDurableOwnershipStore(), false);
});

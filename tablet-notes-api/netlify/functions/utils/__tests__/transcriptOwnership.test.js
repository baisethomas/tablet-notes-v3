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
  // Informational since PR #35 round 2: authorization no longer branches on
  // durability (a positive proof — recorded owner or audio-url owner — is
  // always required), but the flag still documents which store is active.
  assert.equal(isDurableOwnershipStore(), false);
});

// --- ownerIdFromAudioUrl: durable, store-free ownership proof (PR #35 R2) ---

const { ownerIdFromAudioUrl } = require('../transcriptOwnership');

test('extracts the owner from a Supabase signed URL', () => {
  const url = 'https://proj.supabase.co/storage/v1/object/sign/sermon-audio/11111111-1111-1111-1111-111111111111/abc.m4a?token=xyz';
  assert.equal(ownerIdFromAudioUrl(url), '11111111-1111-1111-1111-111111111111');
});

test('extracts the owner from a public object URL', () => {
  const url = 'https://proj.supabase.co/storage/v1/object/public/sermon-audio/user-a/abc.m4a';
  assert.equal(ownerIdFromAudioUrl(url), 'user-a');
});

test('decodes percent-encoded path segments', () => {
  const url = 'https://proj.supabase.co/storage/v1/object/sign/sermon-audio/user%2Da/abc.m4a?token=t';
  assert.equal(ownerIdFromAudioUrl(url), 'user-a');
});

test('returns null when the bucket is absent', () => {
  assert.equal(ownerIdFromAudioUrl('https://proj.supabase.co/storage/v1/object/sign/other-bucket/user-a/abc.m4a'), null);
});

test('returns null when no file segment follows the owner', () => {
  // A URL ending at the owner segment is not a real object path.
  assert.equal(ownerIdFromAudioUrl('https://proj.supabase.co/storage/v1/object/sign/sermon-audio/user-a'), null);
});

test('returns null for garbage, empty, and non-string input', () => {
  assert.equal(ownerIdFromAudioUrl('not a url'), null);
  assert.equal(ownerIdFromAudioUrl(''), null);
  assert.equal(ownerIdFromAudioUrl(null), null);
  assert.equal(ownerIdFromAudioUrl(42), null);
});

test('a mismatched audio-url owner cannot prove ownership for another caller', () => {
  const url = 'https://proj.supabase.co/storage/v1/object/sign/sermon-audio/user-a/abc.m4a?token=t';
  assert.notEqual(ownerIdFromAudioUrl(url), 'user-b');
});

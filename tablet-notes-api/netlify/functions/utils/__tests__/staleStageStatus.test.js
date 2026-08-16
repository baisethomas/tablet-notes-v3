const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { isStaleStageRegression } = require('../sermonStatus');

// TAB-90: the server marks a stage complete when a durable job finishes; a
// client with dirty metadata could push its stale `pending` straight back over
// it, and because the job is already terminal nothing ever corrected it again.

const BEFORE = '2026-08-14T10:00:00.000Z';
const AFTER = '2026-08-14T12:00:00.000Z';

const regression = (over) => ({
  serverStatus: 'complete',
  incomingStatus: 'pending',
  serverUpdatedAt: AFTER,
  clientUpdatedAt: BEFORE,
  ...over
});

test('a stale push cannot undo a completed stage', () => {
  assert.equal(isStaleStageRegression(regression()), true);
});

test('a deliberate change made after the server wrote is allowed through', () => {
  // This is the case that rules out a blunt "never regress from complete":
  // user-initiated re-transcription legitimately sets pending.
  assert.equal(
    isStaleStageRegression(regression({ serverUpdatedAt: BEFORE, clientUpdatedAt: AFTER })),
    false
  );
});

test('an identical timestamp is not newer, so the completion stands', () => {
  // Ties go to the server. A client that has not changed since the completion
  // has nothing new to say about it.
  assert.equal(
    isStaleStageRegression(regression({ serverUpdatedAt: AFTER, clientUpdatedAt: AFTER })),
    true
  );
});

test('only a completed stage is protected', () => {
  for (const serverStatus of ['pending', 'processing', 'failed', null, undefined]) {
    assert.equal(
      isStaleStageRegression(regression({ serverStatus })),
      false,
      `server "${serverStatus}" has nothing to protect`
    );
  }
});

test('complete -> complete is not a regression', () => {
  assert.equal(isStaleStageRegression(regression({ incomingStatus: 'complete' })), false);
});

test('a client that sends no status is untouched', () => {
  assert.equal(isStaleStageRegression(regression({ incomingStatus: undefined })), false);
  assert.equal(isStaleStageRegression(regression({ incomingStatus: null })), false);
});

test('an unusable timestamp fails safe — the completion is kept', () => {
  for (const clientUpdatedAt of [undefined, null, '', 'not-a-date', 12345]) {
    assert.equal(
      isStaleStageRegression(regression({ clientUpdatedAt })),
      true,
      `client timestamp ${JSON.stringify(clientUpdatedAt)} must not be trusted to regress`
    );
  }
  // Same on the other side: an unreadable server timestamp must not open a hole.
  assert.equal(isStaleStageRegression(regression({ serverUpdatedAt: 'nonsense' })), true);
});

// --- wiring -----------------------------------------------------------------

const SRC = fs.readFileSync(path.join(__dirname, '../../update-sermon.js'), 'utf8');

test('update-sermon fetches what the guard needs', () => {
  assert.match(
    SRC,
    /\.select\('id, user_id, updated_at, transcription_status, summary_status'\)/,
    'the guard cannot compare against fields the endpoint never loaded'
  );
});

test('both stage statuses go through the guard, not straight into the update', () => {
  assert.doesNotMatch(
    SRC,
    /updateData\.transcription_status = body\.transcriptionStatus/,
    'the unguarded assignment is what TAB-90 is about'
  );
  assert.doesNotMatch(SRC, /updateData\.summary_status = body\.summaryStatus/);
  assert.match(SRC, /isStaleStageRegression\(/);
});

test('a dropped status does not discard the rest of the update', () => {
  // The user really did edit the title; only the stale status is refused.
  const loop = SRC.slice(SRC.indexOf('const droppedStages'), SRC.indexOf('updateData.updated_at'));
  assert.match(loop, /continue;/, 'a stale stage is skipped, not fatal');
  assert.doesNotMatch(loop, /createErrorResponse/, 'a stale stage must not fail the whole request');
});

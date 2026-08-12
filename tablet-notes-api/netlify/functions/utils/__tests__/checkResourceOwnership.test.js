const test = require('node:test');
const assert = require('node:assert');

const { checkResourceOwnership } = require('../security');

// This helper gates transcribe.js and jobs.js against a client-supplied path,
// both of which then sign the object with the SERVICE ROLE key. It had no test
// coverage and accepted traversal (TAB-84).

const USER = { id: '94771a20-c9e7-4a85-ad3d-b8ac29a23501' };
const OTHER = '11111111-2222-3333-4444-555555555555';

test('accepts a path under the caller prefix', () => {
  assert.ok(checkResourceOwnership(USER, `${USER.id}/recording.m4a`));
});

test('rejects another user\'s path', () => {
  assert.ok(!checkResourceOwnership(USER, `${OTHER}/recording.m4a`));
});

test('rejects traversal that escapes the prefix', () => {
  const escaping = `${USER.id}/../${OTHER}/victim.m4a`;
  // The bug: this satisfies the prefix test the function is built on.
  assert.ok(escaping.startsWith(`${USER.id}/`), 'precondition');
  assert.ok(!checkResourceOwnership(USER, escaping), 'must still be refused');
});

test('rejects a sibling prefix that merely starts with the id', () => {
  assert.ok(!checkResourceOwnership(USER, `${USER.id}-evil/x.m4a`));
});

test('rejects a bare filename — callers of this helper require a namespaced path', () => {
  assert.ok(!checkResourceOwnership(USER, 'recording.m4a'));
});

test('rejects missing user, missing path, and non-strings', () => {
  assert.ok(!checkResourceOwnership(null, `${USER.id}/a.m4a`));
  assert.ok(!checkResourceOwnership({}, `${USER.id}/a.m4a`));
  assert.ok(!checkResourceOwnership(USER, ''));
  assert.ok(!checkResourceOwnership(USER, null));
  assert.ok(!checkResourceOwnership(USER, 42));
  assert.ok(!checkResourceOwnership(USER, {}));
});

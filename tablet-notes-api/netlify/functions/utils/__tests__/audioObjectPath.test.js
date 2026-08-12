const test = require('node:test');
const assert = require('node:assert');

const { resolveAudioObjectPath } = require('../audioObjectPath');

const USER = '94771a20-c9e7-4a85-ad3d-b8ac29a23501';
const OBJ = 'ba06a031-4afd-412a-8eb9-972b611fffd4.m4a';
const PATH = `${USER}/${OBJ}`;
const URL_FOR_PATH = `https://ref.supabase.co/storage/v1/object/public/sermon-audio/${PATH}`;

test('prefers audio_file_path', () => {
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: PATH, audio_file_url: URL_FOR_PATH }, { ownerId: USER }),
    PATH
  );
});

test('matches what URL-splitting produced — the switch is behaviour-preserving', () => {
  // Verified against production: for all 425 rows audio_file_path is identical
  // to the URL's /sermon-audio/ suffix. This pins that equivalence.
  const sermon = { audio_file_path: PATH, audio_file_url: URL_FOR_PATH };
  const legacy = sermon.audio_file_url.split('/sermon-audio/')[1];
  assert.strictEqual(resolveAudioObjectPath(sermon, { ownerId: USER }), legacy);
});

test('falls back to the URL when no path is stored', () => {
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: null, audio_file_url: URL_FOR_PATH }, { ownerId: USER }),
    PATH
  );
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: '   ', audio_file_url: URL_FOR_PATH }, { ownerId: USER }),
    PATH
  );
});

test('handles legacy bare-filename rows (3 exist in prod)', () => {
  const bare = 'sermon_616BC871-EA80-46F4-9E07-4FF23C21A238.m4a';
  assert.strictEqual(resolveAudioObjectPath({ audio_file_path: bare }), bare);
});

test('returns null when there is nothing to delete, rather than a bogus path', () => {
  // The caller must skip the storage delete entirely — never call remove([''])
  // or remove(['undefined']), which could target an unintended object.
  assert.strictEqual(resolveAudioObjectPath({}), null);
  assert.strictEqual(resolveAudioObjectPath(null), null);
  assert.strictEqual(resolveAudioObjectPath({ audio_file_url: 'https://x/no-marker/f.m4a' }), null);
  assert.strictEqual(resolveAudioObjectPath({ audio_file_url: 'not-a-url' }), null);
  assert.strictEqual(resolveAudioObjectPath({ audio_file_path: 42 }), null);
});

test('a URL ending exactly at the marker yields null, not an empty path', () => {
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_url: 'https://ref/storage/v1/object/public/sermon-audio/' }),
    null
  );
});

// --- ownership boundary (PR #45 review, P1 security) ---
// `create-sermon` persists client-supplied audio_file_path / audio_file_url
// with no validation, and delete-sermon removes with the SERVICE ROLE key,
// which bypasses RLS. Owning the row must not imply owning the object.

const OTHER = '11111111-2222-3333-4444-555555555555';

test('refuses to delete an object under ANOTHER user\'s prefix', () => {
  const victimPath = `${OTHER}/secret-recording.m4a`;
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: victimPath }, { ownerId: USER }),
    null,
    'a crafted path must not resolve — this would permanently delete their audio'
  );
});

test('refuses a victim path smuggled through the URL fallback too', () => {
  const victimUrl = `https://ref.supabase.co/storage/v1/object/public/sermon-audio/${OTHER}/secret.m4a`;
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_url: victimUrl }, { ownerId: USER }),
    null
  );
});

test('refuses traversal attempts', () => {
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: `${USER}/../${OTHER}/secret.m4a` }, { ownerId: USER }),
    null
  );
});

test('refuses a prefix that merely starts with the owner id', () => {
  // `${USER}-evil/...` must not satisfy a startsWith check on the raw id.
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: `${USER}-evil/x.m4a` }, { ownerId: USER }),
    null
  );
});

test('a namespaced path with no known owner resolves to null, not to the path', () => {
  assert.strictEqual(resolveAudioObjectPath({ audio_file_path: PATH }), null);
});

test('legacy bare filenames still resolve — they cannot name another user\'s object', () => {
  const bare = 'sermon_616BC871-EA80-46F4-9E07-4FF23C21A238.m4a';
  assert.strictEqual(resolveAudioObjectPath({ audio_file_path: bare }, { ownerId: USER }), bare);
});

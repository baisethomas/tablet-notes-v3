const test = require('node:test');
const assert = require('node:assert');

const { resolveAudioObjectPath } = require('../audioObjectPath');

const USER = '94771a20-c9e7-4a85-ad3d-b8ac29a23501';
const OBJ = 'ba06a031-4afd-412a-8eb9-972b611fffd4.m4a';
const PATH = `${USER}/${OBJ}`;
const URL_FOR_PATH = `https://ref.supabase.co/storage/v1/object/public/sermon-audio/${PATH}`;

test('prefers audio_file_path', () => {
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: PATH, audio_file_url: URL_FOR_PATH }),
    PATH
  );
});

test('matches what URL-splitting produced — the switch is behaviour-preserving', () => {
  // Verified against production: for all 425 rows audio_file_path is identical
  // to the URL's /sermon-audio/ suffix. This pins that equivalence.
  const sermon = { audio_file_path: PATH, audio_file_url: URL_FOR_PATH };
  const legacy = sermon.audio_file_url.split('/sermon-audio/')[1];
  assert.strictEqual(resolveAudioObjectPath(sermon), legacy);
});

test('falls back to the URL when no path is stored', () => {
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: null, audio_file_url: URL_FOR_PATH }),
    PATH
  );
  assert.strictEqual(
    resolveAudioObjectPath({ audio_file_path: '   ', audio_file_url: URL_FOR_PATH }),
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

const BUCKET_MARKER = '/sermon-audio/';

/**
 * Resolves which storage object a sermon's audio lives at, for deletion (TAB-82).
 *
 * `delete-sermon` used to derive this by string-splitting `audio_file_url` on
 * `/sermon-audio/`. That coupled deletion to a column that is otherwise unused
 * and, as it happens, unusable: every stored URL is a `/object/public/` link to
 * a private bucket, so it 404s if anyone ever dereferences it. Nothing could
 * change or drop that column without silently skipping storage deletion and
 * orphaning ~100MB objects.
 *
 * `audio_file_path` is the authoritative value — it is what
 * `generate-upload-url` returned and what the upload actually wrote to. Checked
 * against production before switching: for all 425 rows `audio_file_path` is
 * byte-identical to the URL's `/sermon-audio/` suffix, so this is behaviour-
 * preserving today and correct going forward.
 *
 * The URL remains a fallback purely so a row that somehow lacks a path still
 * gets its audio cleaned up.
 */
function resolveAudioObjectPath(sermon) {
  if (!sermon) return null;

  const path = typeof sermon.audio_file_path === 'string'
    ? sermon.audio_file_path.trim()
    : '';
  if (path) return path;

  // Legacy fallback: recover the object path from the stored URL.
  const url = typeof sermon.audio_file_url === 'string' ? sermon.audio_file_url : '';
  if (url.includes(BUCKET_MARKER)) {
    const tail = url.split(BUCKET_MARKER)[1];
    if (tail) return tail;
  }

  return null;
}

module.exports = { resolveAudioObjectPath, BUCKET_MARKER };

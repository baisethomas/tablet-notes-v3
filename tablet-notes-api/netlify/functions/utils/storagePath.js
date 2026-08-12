const { randomUUID } = require('crypto');

/**
 * Builds the storage object path for a sermon's audio (TAB-73).
 *
 * Historically this was `${userId}/${randomUUID()}.${ext}` — a fresh path on
 * every call. That made resuming impossible (each retry wrote a different
 * object) and leaked the abandoned partial uploads, which nothing reaps. A
 * 2-hour sermon is ~100MB, so a retry loop could strand hundreds of megabytes.
 *
 * When the client supplies its `sermonLocalId` the path becomes **stable**:
 * every attempt for that sermon addresses the same object, so a retry replaces
 * the partial instead of orphaning it.
 *
 * `sermonLocalId` is optional on purpose. Already-shipped builds do not send it,
 * and they must keep working — they simply keep the old random-path behaviour
 * rather than failing.
 */

/** Only lowercase alphanumerics — the extension is interpolated into a path. */
const SAFE_EXTENSION = /^[a-z0-9]{1,8}$/;
const DEFAULT_EXTENSION = 'm4a';

function safeExtension(fileName) {
  const parts = String(fileName || '').split('.');
  if (parts.length < 2) return DEFAULT_EXTENSION;
  const ext = parts.pop().toLowerCase();
  return SAFE_EXTENSION.test(ext) ? ext : DEFAULT_EXTENSION;
}

/**
 * @returns {{ path: string, stable: boolean }} `stable` tells the caller whether
 * it may upsert. Overwriting is only safe for a path derived from the sermon id;
 * a random path must never upsert, since a collision would be someone else's
 * object rather than an earlier attempt at this one.
 */
function buildAudioObjectPath({ userId, sermonLocalId, fileName }) {
  if (!userId) {
    throw new Error('buildAudioObjectPath requires a userId');
  }

  const ext = safeExtension(fileName);

  if (isUuid(sermonLocalId)) {
    return { path: `${userId}/${sermonLocalId}.${ext}`, stable: true };
  }

  return { path: `${userId}/${randomUUID()}.${ext}`, stable: false };
}

/**
 * Deliberately strict. `sermonLocalId` reaches the path unescaped, so anything
 * that is not plainly a UUID falls back to the random path rather than being
 * sanitized into something that merely looks safe.
 */
function isUuid(value) {
  return typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

module.exports = { buildAudioObjectPath, isUuid, safeExtension };

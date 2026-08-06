const { Redis } = require('@upstash/redis');

// Interim server-side binding between an AssemblyAI transcript ID and the
// user who submitted it (TAB-69). Before this existed, ownership of a status
// read was "verified" against a client-supplied userId field that could simply
// be omitted, letting any authenticated user read any transcript by ID.
//
// The durable fix is the Phase 2 processing_jobs table (TAB-72); this module
// is deliberately small so it can be deleted when that lands. Mappings are
// best-effort: a missing mapping (legacy in-flight job, Redis eviction, cold
// container on the in-memory fallback) must NOT block a legitimate status
// check, so callers treat "unknown" as allow-with-logging and a *mismatched*
// owner as a hard deny.

// 24h covers AssemblyAI's worst-case queue + processing time for a long sermon.
const OWNER_TTL_SECONDS = 24 * 60 * 60;
const KEY_PREFIX = 'transcript_owner:';

let redis = null;
if (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN) {
  redis = new Redis({
    url: process.env.UPSTASH_REDIS_REST_URL,
    token: process.env.UPSTASH_REDIS_REST_TOKEN,
  });
}

// Per-container fallback when Redis is not configured. Not shared across
// containers, so it only best-effort protects; the fail-open-on-unknown
// posture above makes that acceptable for this interim module.
const memoryOwners = new Map();
const MEMORY_MAX_ENTRIES = 10000;

function pruneMemory(now) {
  for (const [key, entry] of memoryOwners) {
    if (entry.expiresAt <= now) {
      memoryOwners.delete(key);
    }
  }
}

/**
 * Record that `userId` owns AssemblyAI transcript `transcriptId`.
 * Best-effort: never throws — a failure to record must not fail the
 * transcription submission it follows.
 */
async function recordTranscriptOwner(transcriptId, userId) {
  if (!transcriptId || !userId) return false;
  const key = `${KEY_PREFIX}${transcriptId}`;

  try {
    if (redis) {
      await redis.set(key, userId, { ex: OWNER_TTL_SECONDS });
      return true;
    }

    const now = Date.now();
    if (memoryOwners.size >= MEMORY_MAX_ENTRIES) {
      pruneMemory(now);
    }
    if (memoryOwners.size >= MEMORY_MAX_ENTRIES) {
      return false;
    }
    memoryOwners.set(key, {
      userId,
      expiresAt: now + OWNER_TTL_SECONDS * 1000,
    });
    return true;
  } catch (error) {
    console.error('[TranscriptOwnership] Failed to record owner:', error);
    return false;
  }
}

/**
 * Look up the recorded owner of a transcript.
 * @returns {Promise<string|null>} the owner's userId, or null when unknown
 * (never submitted through this path, expired, or the store is unavailable).
 */
async function getTranscriptOwner(transcriptId) {
  if (!transcriptId) return null;
  const key = `${KEY_PREFIX}${transcriptId}`;

  try {
    if (redis) {
      const owner = await redis.get(key);
      return typeof owner === 'string' && owner.length > 0 ? owner : null;
    }

    const entry = memoryOwners.get(key);
    if (!entry) return null;
    if (entry.expiresAt <= Date.now()) {
      memoryOwners.delete(key);
      return null;
    }
    return entry.userId;
  } catch (error) {
    console.error('[TranscriptOwnership] Failed to look up owner:', error);
    return null;
  }
}

module.exports = {
  recordTranscriptOwner,
  getTranscriptOwner,
  OWNER_TTL_SECONDS,
  // Exported for tests only.
  _memoryOwners: memoryOwners,
};

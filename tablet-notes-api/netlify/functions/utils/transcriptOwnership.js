const { Redis } = require('@upstash/redis');

// Interim server-side binding between an AssemblyAI transcript ID and the
// user who submitted it (TAB-69). Before this existed, ownership of a status
// read was "verified" against a client-supplied userId field that could simply
// be omitted, letting any authenticated user read any transcript by ID.
//
// The durable fix is the Phase 2 processing_jobs table (TAB-72); this module
// is deliberately small so it can be deleted when that lands.
//
// Fail-closed policy (PR #35 review): when the store is DURABLE (Redis),
// an unknown mapping denies the read and a store outage is a retryable
// unavailability — "we can't prove ownership" must not authorize the read.
// Only the per-container in-memory fallback (Redis not configured) reports
// unknowns as non-authoritative, because there submission and polling
// routinely land on different containers and failing closed would break all
// status polling; that residual gap closes when Upstash is provisioned or
// TAB-72 lands.

// Must outlive any legitimate resumed poll of a slow job. AssemblyAI jobs
// finish in minutes-to-hours; 7 days is comfortable margin without letting
// mappings accumulate forever.
const OWNER_TTL_SECONDS = 7 * 24 * 60 * 60;
const KEY_PREFIX = 'transcript_owner:';

const OWNERSHIP = {
  OWNED: 'owned', // mapping found — result.owner is authoritative
  UNKNOWN: 'unknown', // store answered: no mapping exists
  UNAVAILABLE: 'unavailable', // store errored — could not determine
};

let redis = null;
if (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN) {
  redis = new Redis({
    url: process.env.UPSTASH_REDIS_REST_URL,
    token: process.env.UPSTASH_REDIS_REST_TOKEN,
  });
}

// Per-container fallback when Redis is not configured.
const memoryOwners = new Map();
const MEMORY_MAX_ENTRIES = 10000;

/**
 * Whether the ownership store is durable/shared across containers. When true,
 * an UNKNOWN answer is authoritative and callers must fail closed on it.
 */
function isDurableOwnershipStore() {
  return redis !== null;
}

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
 * Look up the recorded ownership of a transcript.
 * @returns {Promise<{status: 'owned', owner: string} |
 *                   {status: 'unknown'} |
 *                   {status: 'unavailable'}>}
 * Callers combine this with isDurableOwnershipStore(): on a durable store,
 * 'unknown' must deny and 'unavailable' must be a retryable failure.
 */
async function lookupTranscriptOwnership(transcriptId) {
  if (!transcriptId) return { status: OWNERSHIP.UNKNOWN };
  const key = `${KEY_PREFIX}${transcriptId}`;

  try {
    if (redis) {
      const owner = await redis.get(key);
      if (typeof owner === 'string' && owner.length > 0) {
        return { status: OWNERSHIP.OWNED, owner };
      }
      return { status: OWNERSHIP.UNKNOWN };
    }

    const entry = memoryOwners.get(key);
    if (!entry) return { status: OWNERSHIP.UNKNOWN };
    if (entry.expiresAt <= Date.now()) {
      memoryOwners.delete(key);
      return { status: OWNERSHIP.UNKNOWN };
    }
    return { status: OWNERSHIP.OWNED, owner: entry.userId };
  } catch (error) {
    console.error('[TranscriptOwnership] Failed to look up owner:', error);
    return { status: OWNERSHIP.UNAVAILABLE };
  }
}

module.exports = {
  recordTranscriptOwner,
  lookupTranscriptOwnership,
  isDurableOwnershipStore,
  OWNERSHIP,
  OWNER_TTL_SECONDS,
  // Exported for tests only.
  _memoryOwners: memoryOwners,
};

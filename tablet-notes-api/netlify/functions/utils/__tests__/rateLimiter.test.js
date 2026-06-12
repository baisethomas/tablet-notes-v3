const test = require('node:test');
const assert = require('node:assert/strict');
const { RateLimiter, RATE_LIMITS, InMemoryCounterStore } = require('../rateLimiter');

// These tests run without UPSTASH_REDIS_* env vars, exercising the in-memory
// fallback that protects production until Redis is configured (TAB-37).

test('in-memory fallback enforces the per-user limit instead of allowing everything', async () => {
  const limiter = new RateLimiter();
  const max = RATE_LIMITS.upload.maxRequests;

  for (let i = 1; i <= max; i++) {
    const result = await limiter.checkLimit('user-1', 'upload');
    assert.equal(result.allowed, true, `request ${i} of ${max} should be allowed`);
  }

  const blocked = await limiter.checkLimit('user-1', 'upload');
  assert.equal(blocked.allowed, false);
  assert.match(blocked.error, /Rate limit exceeded for user/);
});

test('in-memory fallback tracks identifiers independently', async () => {
  const limiter = new RateLimiter();
  const max = RATE_LIMITS.upload.maxRequests;

  for (let i = 0; i <= max; i++) {
    await limiter.checkLimit('user-1', 'upload');
  }

  const otherUser = await limiter.checkLimit('user-2', 'upload');
  assert.equal(otherUser.allowed, true);
});

test('in-memory fallback enforces the per-IP limit', async () => {
  const limiter = new RateLimiter();
  const ipMax = RATE_LIMITS.ip.maxRequests;

  // Distinct users from the same IP, so only the IP counter can trip.
  let lastResult;
  for (let i = 0; i <= ipMax; i++) {
    lastResult = await limiter.checkLimit(`user-${i}`, 'general', '203.0.113.7');
  }

  assert.equal(lastResult.allowed, false);
  assert.match(lastResult.error, /Rate limit exceeded for IP/);
});

test('rejects unknown limit types', async () => {
  const limiter = new RateLimiter();
  await assert.rejects(() => limiter.checkLimit('user-1', 'nope'), /Invalid rate limit type/);
});

test('store at capacity with unexpired keys cannot grow and fails closed for new keys', async () => {
  const limiter = new RateLimiter();
  limiter.memory = new InMemoryCounterStore(3);

  for (let i = 1; i <= 3; i++) {
    const result = await limiter.checkLimit(`user-${i}`, 'upload');
    assert.equal(result.allowed, true);
  }
  assert.equal(limiter.memory.counters.size, 3);

  // All tracked keys are unexpired (1-hour upload window), so the new key
  // must be rejected rather than admitted past the cap.
  const overflow = await limiter.checkLimit('user-4', 'upload');
  assert.equal(overflow.allowed, false);
  assert.match(overflow.error, /at capacity/);
  assert.equal(limiter.memory.counters.size, 3);
});

test('existing keys keep counting while the store is at capacity', async () => {
  const limiter = new RateLimiter();
  limiter.memory = new InMemoryCounterStore(3);

  for (let i = 1; i <= 3; i++) {
    await limiter.checkLimit(`user-${i}`, 'upload');
  }

  const tracked = await limiter.checkLimit('user-1', 'upload');
  assert.equal(tracked.allowed, true);
  assert.equal(tracked.currentCount, 2);
});

test('expired entries are pruned to admit new keys at capacity', () => {
  const store = new InMemoryCounterStore(2);
  const past = Date.now() - 1000;
  const future = Date.now() + 60_000;

  assert.equal(store.increment('stale', past), 1);
  assert.equal(store.increment('live', future), 1);

  // Store is full, but 'stale' is expired — pruning makes room.
  assert.equal(store.increment('fresh', future), 1);
  assert.equal(store.counters.size, 2);
  assert.equal(store.counters.has('stale'), false);
});

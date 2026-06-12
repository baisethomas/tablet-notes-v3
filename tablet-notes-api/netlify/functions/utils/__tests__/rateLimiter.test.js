const test = require('node:test');
const assert = require('node:assert/strict');
const { RateLimiter, RATE_LIMITS } = require('../rateLimiter');

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

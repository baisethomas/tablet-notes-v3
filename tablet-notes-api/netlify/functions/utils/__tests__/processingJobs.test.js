const test = require('node:test');
const assert = require('node:assert/strict');
const {
  JOB_STATUS,
  DEFAULT_MAX_ATTEMPTS,
  idempotencyKey,
  backoffMs,
  nextAttemptAt,
  isStale,
  planFailure,
  interpretWebhook,
  secretMatches
} = require('../processingJobs');

const SERMON = '11111111-1111-1111-1111-111111111111';

// --- idempotency ---

test('idempotencyKey is stable per (sermon, kind)', () => {
  assert.equal(idempotencyKey(SERMON, 'transcription'), `${SERMON}:transcription`);
  assert.equal(idempotencyKey(SERMON, 'transcription'), idempotencyKey(SERMON, 'transcription'));
  assert.notEqual(idempotencyKey(SERMON, 'transcription'), idempotencyKey(SERMON, 'summary'));
});

test('idempotencyKey rejects missing inputs rather than producing a collidable key', () => {
  assert.throws(() => idempotencyKey(null, 'transcription'));
  assert.throws(() => idempotencyKey(SERMON, null));
});

// --- backoff ---

test('backoff grows exponentially and is capped', () => {
  assert.equal(backoffMs(1), 60_000);
  assert.equal(backoffMs(2), 120_000);
  assert.equal(backoffMs(3), 240_000);
  assert.equal(backoffMs(50), 1_800_000); // capped at 30m
});

test('backoff treats invalid attempts as the first attempt', () => {
  assert.equal(backoffMs(0), 60_000);
  assert.equal(backoffMs(undefined), 60_000);
});

test('nextAttemptAt returns an ISO timestamp in the future', () => {
  const now = Date.UTC(2026, 0, 1);
  assert.equal(nextAttemptAt(1, { now }), new Date(now + 60_000).toISOString());
});

// --- failure planning ---

test('a retryable failure re-queues with backoff and increments attempts', () => {
  const plan = planFailure({ attempts: 1, max_attempts: 5 }, new Error('provider timeout'));
  assert.equal(plan.status, JOB_STATUS.QUEUED);
  assert.equal(plan.attempts, 2);
  assert.equal(plan.last_error, 'provider timeout');
  assert.ok(plan.next_attempt_at);
});

test('exhausting attempts marks the job dead, not silently stalled', () => {
  const plan = planFailure({ attempts: DEFAULT_MAX_ATTEMPTS - 1, max_attempts: DEFAULT_MAX_ATTEMPTS }, 'boom');
  assert.equal(plan.status, JOB_STATUS.DEAD);
  assert.equal(plan.attempts, DEFAULT_MAX_ATTEMPTS);
  assert.equal(plan.next_attempt_at, null);
  assert.ok(plan.completed_at);
});

test('planFailure accepts a string or an Error', () => {
  assert.equal(planFailure({ attempts: 0 }, 'plain string').last_error, 'plain string');
  assert.equal(planFailure({ attempts: 0 }, new Error('an error')).last_error, 'an error');
  assert.equal(planFailure({ attempts: 0 }, {}).last_error, 'unknown error');
});

// --- staleness ---

test('a job submitted long ago with no terminal webhook is stale', () => {
  const now = Date.UTC(2026, 0, 2);
  const job = {
    status: JOB_STATUS.SUBMITTED,
    submitted_at: new Date(now - 3 * 60 * 60 * 1000).toISOString()
  };
  assert.equal(isStale(job, { now }), true);
});

test('a recently submitted job is not stale', () => {
  const now = Date.UTC(2026, 0, 2);
  const job = {
    status: JOB_STATUS.SUBMITTED,
    submitted_at: new Date(now - 5 * 60 * 1000).toISOString()
  };
  assert.equal(isStale(job, { now }), false);
});

test('terminal jobs are never stale', () => {
  const now = Date.UTC(2026, 0, 2);
  const old = new Date(now - 99 * 60 * 60 * 1000).toISOString();
  assert.equal(isStale({ status: JOB_STATUS.DONE, submitted_at: old }, { now }), false);
  assert.equal(isStale({ status: JOB_STATUS.DEAD, submitted_at: old }, { now }), false);
});

test('isStale tolerates missing or malformed timestamps', () => {
  assert.equal(isStale(null), false);
  assert.equal(isStale({ status: JOB_STATUS.SUBMITTED }), false);
  assert.equal(isStale({ status: JOB_STATUS.SUBMITTED, submitted_at: 'not-a-date' }), false);
});

// --- webhook interpretation ---

test('interprets a completed callback', () => {
  const result = interpretWebhook({ transcript_id: 'tr-1', status: 'completed' });
  assert.deepEqual(result, { valid: true, transcriptId: 'tr-1', outcome: 'completed' });
});

test('interprets an error callback and carries the reason', () => {
  const result = interpretWebhook({ transcript_id: 'tr-2', status: 'error', error: 'audio unreadable' });
  assert.equal(result.valid, true);
  assert.equal(result.outcome, 'error');
  assert.equal(result.error, 'audio unreadable');
});

test('accepts the dotted event-name variants', () => {
  assert.equal(interpretWebhook({ transcript_id: 't', status: 'transcript.completed' }).outcome, 'completed');
  assert.equal(interpretWebhook({ transcript_id: 't', status: 'transcript.error' }).outcome, 'error');
});

test('rejects callbacks with no transcript id', () => {
  assert.equal(interpretWebhook({ status: 'completed' }).valid, false);
  assert.equal(interpretWebhook({}).valid, false);
  assert.equal(interpretWebhook(null).valid, false);
});

test('ignores intermediate statuses rather than acting on them', () => {
  const result = interpretWebhook({ transcript_id: 't', status: 'processing' });
  assert.equal(result.valid, false);
  assert.match(result.reason, /processing/);
});

// --- webhook secret ---

test('secretMatches accepts only an exact match', () => {
  assert.equal(secretMatches('s3cret-value', 's3cret-value'), true);
  assert.equal(secretMatches('s3cret-value', 's3cret-valuE'), false);
  assert.equal(secretMatches('short', 'a-much-longer-secret'), false);
});

test('secretMatches rejects missing or non-string input (fails closed)', () => {
  assert.equal(secretMatches(undefined, 'secret'), false);
  assert.equal(secretMatches('secret', undefined), false);
  assert.equal(secretMatches(null, null), false);
  assert.equal(secretMatches(123, 123), false);
});

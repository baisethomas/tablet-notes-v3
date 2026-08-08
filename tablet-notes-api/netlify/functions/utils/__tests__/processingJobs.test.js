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

// --- summary chaining predicate (PR #37 review round 1) ---
// The reaper's lost-webhook recovery silently skipped summary chaining because
// the logic existed twice. It now lives here, once, used by the single shared
// completion writer that both the webhook and the reaper call.

const { shouldChainSummary } = require('../processingJobs');

test('a completed transcription with real text chains a summary', () => {
  const job = { kind: 'transcription' };
  assert.equal(shouldChainSummary(job, 'x'.repeat(50)), true);
  assert.equal(shouldChainSummary(job, 'A real sermon transcript that is comfortably long enough.'), true);
});

test('a too-short transcript does not chain a summary that would only fail', () => {
  const job = { kind: 'transcription' };
  assert.equal(shouldChainSummary(job, 'too short'), false);
  assert.equal(shouldChainSummary(job, '   '.repeat(40)), false); // whitespace doesn't count
  assert.equal(shouldChainSummary(job, ''), false);
  assert.equal(shouldChainSummary(job, null), false);
});

test('a summary job never chains another summary', () => {
  assert.equal(shouldChainSummary({ kind: 'summary' }, 'x'.repeat(500)), false);
  assert.equal(shouldChainSummary({}, 'x'.repeat(500)), false);
  assert.equal(shouldChainSummary(null, 'x'.repeat(500)), false);
});

// --- durable provider handoff (PR #37 review round 3) ---
// Resolving a callback only by provider_job_id assumes our write of that id
// succeeded. It can fail, and a submit can time out after AssemblyAI already
// accepted the audio. These helpers are what keep a paid transcription from
// being discarded as "unknown" and re-billed.

const {
  webhookUrlFor,
  jobIdFromWebhookQuery,
  classifySubmitFailure,
  handoffGraceExpired,
  HANDOFF_GRACE_MS
} = require('../processingJobs');

const JOB_ID = '9f1c1e2a-4a1e-4f6b-9a3d-2b7c5d8e1f04';

test('the callback URL carries our own job id', () => {
  assert.equal(
    webhookUrlFor('https://api.example.com', JOB_ID),
    `https://api.example.com/api/assemblyai-webhook?job=${JOB_ID}`
  );
});

test('the callback URL tolerates a trailing slash on the base', () => {
  assert.equal(
    webhookUrlFor('https://api.example.com/', JOB_ID),
    `https://api.example.com/api/assemblyai-webhook?job=${JOB_ID}`
  );
});

test('our job id round-trips out of the callback query', () => {
  assert.equal(jobIdFromWebhookQuery({ job: JOB_ID }), JOB_ID);
  assert.equal(jobIdFromWebhookQuery({ job: `  ${JOB_ID}  ` }), JOB_ID);
});

test('a non-uuid job param is rejected rather than passed to a query', () => {
  assert.equal(jobIdFromWebhookQuery({ job: "' or 1=1--" }), null);
  assert.equal(jobIdFromWebhookQuery({ job: '' }), null);
  assert.equal(jobIdFromWebhookQuery({ job: 12345 }), null);
  assert.equal(jobIdFromWebhookQuery({}), null);
  assert.equal(jobIdFromWebhookQuery(null), null);
});

test('only provably-local failures are safe to re-queue', () => {
  assert.equal(classifySubmitFailure(new Error('Circuit breaker is OPEN')), 'not-sent');
  assert.equal(classifySubmitFailure(new Error('getaddrinfo ENOTFOUND api.assemblyai.com')), 'not-sent');
  assert.equal(classifySubmitFailure(new Error('connect ECONNREFUSED 1.2.3.4:443')), 'not-sent');
});

test('a timeout is treated as uncertain, never as not-sent', () => {
  // The critical case: the provider may have accepted the audio and answered
  // slowly. Re-queuing here bills a second transcription and orphans the first.
  assert.equal(classifySubmitFailure(new Error('Operation timed out')), 'uncertain');
  assert.equal(classifySubmitFailure(new Error('socket hang up')), 'uncertain');
  assert.equal(classifySubmitFailure(new Error('500 Internal Server Error')), 'uncertain');
  assert.equal(classifySubmitFailure(undefined), 'uncertain');
});

test('an unresolved handoff is left alone inside the grace window', () => {
  const now = Date.UTC(2026, 0, 2);
  const job = { submitted_at: new Date(now - 30 * 60 * 1000).toISOString() };
  assert.equal(handoffGraceExpired(job, { now }), false);
});

test('an unresolved handoff is re-queued once the grace window passes', () => {
  const now = Date.UTC(2026, 0, 2);
  const job = { submitted_at: new Date(now - HANDOFF_GRACE_MS - 1000).toISOString() };
  assert.equal(handoffGraceExpired(job, { now }), true);
});

test('the grace window outlasts the staleness window, so reconcile never races it', () => {
  // isStale fires at 2h; if the grace window were shorter, a job with an
  // unresolved handoff would be re-queued by the stale path before the
  // callback had a fair chance to land.
  assert.ok(HANDOFF_GRACE_MS > 2 * 60 * 60 * 1000);
});

test('handoffGraceExpired fails toward re-queuing when it has no timestamp', () => {
  // With no reference point there is nothing to wait for; a job that can never
  // resolve must not sit in 'submitted' forever.
  assert.equal(handoffGraceExpired({}), true);
  assert.equal(handoffGraceExpired({ submitted_at: 'not-a-date' }), true);
  assert.equal(handoffGraceExpired(null), true);
});

// --- adopting an existing provider job (PR #37 review round 4) ---
// Re-queuing on an expired grace window alone is still a guess: a slow-but-
// running transcription would be submitted twice. The storage path is the join
// key both sides share, so we can ask instead of guessing.

const { matchProviderTranscript } = require('../processingJobs');

const AUDIO_PATH = 'user-abc/sermon-2026-08-08.m4a';
const JOB_WITH_AUDIO = { audio_file_path: AUDIO_PATH };

test('matches a provider transcript by the storage path inside its signed URL', () => {
  const transcripts = [
    { id: 'tr-other', audio_url: 'https://x.supabase.co/storage/v1/object/sign/sermon-audio/user-zzz/other.m4a?token=aaa' },
    { id: 'tr-mine', audio_url: `https://x.supabase.co/storage/v1/object/sign/sermon-audio/${AUDIO_PATH}?token=bbb` }
  ];
  assert.equal(matchProviderTranscript(transcripts, JOB_WITH_AUDIO).id, 'tr-mine');
});

test('matches even though the signed-URL token differs from the one we submitted', () => {
  // The whole point: tokens are re-minted per submit, the object path is not.
  const transcripts = [
    { id: 'tr-mine', audio_url: `https://x.supabase.co/storage/v1/object/sign/sermon-audio/${AUDIO_PATH}?token=totally-different` }
  ];
  assert.equal(matchProviderTranscript(transcripts, JOB_WITH_AUDIO).id, 'tr-mine');
});

test('matches a percent-encoded path', () => {
  const encoded = 'https://x.supabase.co/storage/v1/object/sign/sermon-audio/user-abc/my%20sermon.m4a?token=c';
  const job = { audio_file_path: 'user-abc/my sermon.m4a' };
  assert.equal(matchProviderTranscript([{ id: 'tr-enc', audio_url: encoded }], job).id, 'tr-enc');
});

test('returns null when the audio is genuinely not at the provider', () => {
  // Only then is resubmitting the right move.
  const transcripts = [
    { id: 'tr-other', audio_url: 'https://x.supabase.co/storage/v1/object/sign/sermon-audio/user-zzz/other.m4a?token=a' }
  ];
  assert.equal(matchProviderTranscript(transcripts, JOB_WITH_AUDIO), null);
  assert.equal(matchProviderTranscript([], JOB_WITH_AUDIO), null);
});

test('adopts the newest when duplicates already exist rather than creating a third', () => {
  const transcripts = [
    { id: 'tr-old', created: '2026-08-08T01:00:00Z', audio_url: `https://x/sermon-audio/${AUDIO_PATH}?token=a` },
    { id: 'tr-new', created: '2026-08-08T05:00:00Z', audio_url: `https://x/sermon-audio/${AUDIO_PATH}?token=b` }
  ];
  assert.equal(matchProviderTranscript(transcripts, JOB_WITH_AUDIO).id, 'tr-new');
});

test('matchProviderTranscript tolerates junk input rather than throwing mid-sweep', () => {
  assert.equal(matchProviderTranscript(null, JOB_WITH_AUDIO), null);
  assert.equal(matchProviderTranscript([{ id: 'x' }], JOB_WITH_AUDIO), null);
  assert.equal(matchProviderTranscript([{ id: 'x', audio_url: 42 }], JOB_WITH_AUDIO), null);
  assert.equal(matchProviderTranscript([{ id: 'x', audio_url: '%%%' }], JOB_WITH_AUDIO), null);
  assert.equal(matchProviderTranscript([{ id: 'x', audio_url: 'anything' }], {}), null);
  assert.equal(matchProviderTranscript([{ id: 'x', audio_url: 'anything' }], null), null);
});

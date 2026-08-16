const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { schemas } = require('../validator');
const { isExhaustedWithoutRetry, JOB_STATUS } = require('../processingJobs');

// TAB-85: an exhausted job must not be resurrected by an automatic sweep.
//
// The loop: the client re-POSTs every pending/failed sermon on each launch,
// jobs.js revived the dead row with attempts=0, and the reaper spent five more
// provider calls before it died again. Forever, for a recording that could
// never succeed.

// --- the decision, actually executed ---------------------------------------
//
// These call the predicate rather than reading the source. The first cut of
// this fix asserted on source text and shipped a ReferenceError past a green
// suite (PR #50 review) — the code "looked right" and was never run.

test('a dead job is left alone for an automatic dispatch', () => {
  assert.equal(isExhaustedWithoutRetry({ status: JOB_STATUS.DEAD }, false), true);
  assert.equal(isExhaustedWithoutRetry({ status: JOB_STATUS.DEAD }, undefined), true);
});

test('a deliberate retry may revive it', () => {
  assert.equal(isExhaustedWithoutRetry({ status: JOB_STATUS.DEAD }, true), false);
});

test('only an exact boolean true counts as a deliberate retry', () => {
  // Guards against a truthy string or 1 slipping through and re-opening the
  // loop; the Joi schema rejects those, this is defence in depth.
  for (const truthy of ['true', 1, 'yes', {}]) {
    assert.equal(
      isExhaustedWithoutRetry({ status: JOB_STATUS.DEAD }, truthy),
      true,
      `${JSON.stringify(truthy)} must not count as a retry`
    );
  }
});

test('non-dead jobs are unaffected — failed ones still revive automatically', () => {
  // `failed` is a mid-backoff state with attempts remaining; only `dead` is
  // exhausted. Blocking `failed` here would strand recoverable work.
  assert.equal(isExhaustedWithoutRetry({ status: JOB_STATUS.FAILED }, false), false);
  assert.equal(isExhaustedWithoutRetry({ status: JOB_STATUS.QUEUED }, false), false);
  assert.equal(isExhaustedWithoutRetry(null, false), false);
  assert.equal(isExhaustedWithoutRetry(undefined, false), false);
});

// --- the schema half --------------------------------------------------------

test('retry defaults to false, so an automatic dispatch can never revive', () => {
  const { error, value } = schemas.processingJob.validate({
    sermonLocalId: '3ffcc32e-4bac-46fe-b30f-77b623c1b7bd'
  });
  assert.equal(error, undefined);
  assert.equal(value.retry, false, 'omitting retry must mean "do not resurrect"');
});

test('retry can be asked for explicitly', () => {
  const { error, value } = schemas.processingJob.validate({
    sermonLocalId: '3ffcc32e-4bac-46fe-b30f-77b623c1b7bd',
    retry: true
  });
  assert.equal(error, undefined);
  assert.equal(value.retry, true);
});

test('retry is a real boolean — no string coercion', () => {
  // Joi coerces "true" -> true by default, which would have quietly defeated
  // the exact-boolean check in isExhaustedWithoutRetry. .strict() closes it
  // (PR #50 review).
  for (const bad of ['yes-please', 'true', 'false', '1', 1, 0]) {
    const { error } = schemas.processingJob.validate({
      sermonLocalId: '3ffcc32e-4bac-46fe-b30f-77b623c1b7bd',
      retry: bad
    });
    assert.ok(error, `${JSON.stringify(bad)} must be rejected, not coerced`);
  }
});

test('the provider error lookup is short-bounded and truncated', () => {
  const src = fs.readFileSync(path.join(__dirname, '../../assemblyai-webhook.js'), 'utf8');
  assert.match(src, /transcripts\.get\(transcriptId\), 3000\)/,
    'a slow lookup must not stall the webhook into a provider retry');
  assert.match(src, /slice\(0, MAX_ERROR_CHARS\)/,
    'last_error must not store an unbounded provider payload');
});

// --- wiring -----------------------------------------------------------------
//
// The predicate being right is useless if the endpoint reads the wrong thing.
// That is exactly what went wrong: the guard referenced an undeclared `body`.

const JOBS_SRC = fs.readFileSync(path.join(__dirname, '../../jobs.js'), 'utf8');

test('jobs.js reads request fields from validatedData, never from a bare `body`', () => {
  assert.match(JOBS_SRC, /retry = false\s*\n\s*\} = event\.validatedData;/,
    'retry must be destructured from the validated request');
  assert.doesNotMatch(JOBS_SRC, /\bbody\./,
    'jobs.js has no `body` in scope — referencing one throws at runtime');
});

test('the guard precedes the revive, or it is dead code', () => {
  const guardAt = JOBS_SRC.indexOf('isExhaustedWithoutRetry(existing, retry)');
  const reviveAt = JOBS_SRC.indexOf(".in('status', [JOB_STATUS.DEAD, JOB_STATUS.FAILED])");
  assert.ok(guardAt !== -1 && reviveAt !== -1);
  assert.ok(guardAt < reviveAt);
});

// --- provider error detail --------------------------------------------------

const WEBHOOK_SRC = fs.readFileSync(path.join(__dirname, '../../assemblyai-webhook.js'), 'utf8');

test('the webhook prefers the provider’s real error over the generic sentence', () => {
  assert.match(WEBHOOK_SRC, /const detail = await fetchProviderError\(/);
  assert.match(WEBHOOK_SRC, /planFailure\(job, detail \|\| interpreted\.error\)/);
});

test('the error lookup cannot make a failure worse', () => {
  const start = WEBHOOK_SRC.indexOf('async function fetchProviderError');
  const fn = WEBHOOK_SRC.slice(start, WEBHOOK_SRC.indexOf('\n}\n', start));
  assert.match(fn, /try \{/, 'must be wrapped');
  assert.match(fn, /return null/, 'must fall back rather than throw');
  assert.match(fn, /withTimeout/, 'must be bounded — this runs inside a webhook');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { schemas } = require('../validator');

// TAB-85: an exhausted job must not be resurrected by an automatic sweep.
//
// The loop: the client re-POSTs every pending/failed sermon on each launch,
// jobs.js revived the dead row with attempts=0, and the reaper spent five more
// provider calls before it died again. Forever, for a recording that could
// never succeed.

const JOBS_SRC = fs.readFileSync(path.join(__dirname, '../../jobs.js'), 'utf8');

test('the revive branch is gated on an explicit retry', () => {
  // The guard must sit BEFORE the revive, or it cannot prevent anything.
  const guardAt = JOBS_SRC.indexOf('existing.status === JOB_STATUS.DEAD && !body.retry');
  const reviveAt = JOBS_SRC.indexOf('.in(\'status\', [JOB_STATUS.DEAD, JOB_STATUS.FAILED])');

  assert.ok(guardAt !== -1, 'the exhausted-job guard must exist');
  assert.ok(reviveAt !== -1, 'the revive branch must still exist for deliberate retries');
  assert.ok(guardAt < reviveAt, 'the guard must precede the revive, otherwise it is dead code');
});

test('an exhausted job is returned rather than reset', () => {
  const guard = JOBS_SRC.slice(
    JOBS_SRC.indexOf('existing.status === JOB_STATUS.DEAD && !body.retry'),
    JOBS_SRC.indexOf('if (existing) {', JOBS_SRC.indexOf('existing.status === JOB_STATUS.DEAD'))
  );
  assert.match(guard, /reused: true/, 'the caller still gets its job back');
  assert.match(guard, /exhausted: true/, 'and is told why nothing happened');
  assert.doesNotMatch(guard, /attempts:\s*0/, 'attempts must not be reset on this path');
});

// --- the schema half -------------------------------------------------------

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

test('retry is a boolean, not a truthy string', () => {
  const { error } = schemas.processingJob.validate({
    sermonLocalId: '3ffcc32e-4bac-46fe-b30f-77b623c1b7bd',
    retry: 'yes-please'
  });
  assert.ok(error, 'a non-boolean retry must be rejected rather than coerced');
});

// --- provider error detail --------------------------------------------------

const WEBHOOK_SRC = fs.readFileSync(path.join(__dirname, '../../assemblyai-webhook.js'), 'utf8');

test('the webhook stores the provider’s real error, not the generic sentence', () => {
  assert.match(
    WEBHOOK_SRC,
    /const detail = await fetchProviderError\(/,
    'the failure path must look up the real reason'
  );
  assert.match(
    WEBHOOK_SRC,
    /planFailure\(job, detail \|\| interpreted\.error\)/,
    'the detail must be preferred, with the generic string only as fallback'
  );
});

test('the error lookup cannot make a failure worse', () => {
  const fn = WEBHOOK_SRC.slice(
    WEBHOOK_SRC.indexOf('async function fetchProviderError'),
    WEBHOOK_SRC.indexOf('\n}\n', WEBHOOK_SRC.indexOf('async function fetchProviderError'))
  );
  assert.match(fn, /try \{/, 'must be wrapped');
  assert.match(fn, /return null/, 'must fall back rather than throw');
  assert.match(fn, /withTimeout/, 'must be bounded — this runs inside a webhook');
});

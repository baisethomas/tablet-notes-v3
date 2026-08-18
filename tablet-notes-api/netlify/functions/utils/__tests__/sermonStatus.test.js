const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSermonStatusPatch,
  applySermonStageTerminal,
  SERMON_STAGE_COLUMNS
} = require('../sermonStatus');
const { completeTranscriptionJob } = require('../completeTranscription');

const silentLogger = { info() {}, warn() {}, error() {} };
const NOW = '2026-08-14T21:00:00.000Z';

// --- the patch itself -------------------------------------------------------

test('transcription and summary map to their own columns', () => {
  assert.deepEqual(
    buildSermonStatusPatch({ stage: 'transcription', now: NOW }),
    { transcription_status: 'complete', updated_at: NOW }
  );
  assert.deepEqual(
    buildSermonStatusPatch({ stage: 'summary', now: NOW }),
    { summary_status: 'complete', updated_at: NOW }
  );
  // Guards the mapping itself: a stage writing the other stage's column would
  // be a silent no-op of exactly the TAB-89 kind.
  assert.equal(SERMON_STAGE_COLUMNS.transcription, 'transcription_status');
  assert.equal(SERMON_STAGE_COLUMNS.summary, 'summary_status');
});

test('a title is folded into the same write, so the summary path updates once', () => {
  assert.deepEqual(
    buildSermonStatusPatch({ stage: 'summary', title: 'A Real Title', now: NOW }),
    { summary_status: 'complete', updated_at: NOW, title: 'A Real Title' }
  );
});

test('a blank title is never written — it would wipe the existing one', () => {
  for (const title of ['', '   ', null, undefined, 42]) {
    const patch = buildSermonStatusPatch({ stage: 'summary', title, now: NOW });
    assert.ok(!('title' in patch), `${JSON.stringify(title)} must not set title`);
  }
});

test('an unknown stage throws rather than writing nothing', () => {
  // Silently patching no columns is the failure mode this issue is about.
  assert.throws(() => buildSermonStatusPatch({ stage: 'transcript', now: NOW }));
  assert.throws(() => buildSermonStatusPatch({ stage: undefined, now: NOW }));
});

// --- applying it ------------------------------------------------------------

function fakeSermonsTable({ failWith = null } = {}) {
  const updates = [];
  return {
    updates,
    from(table) {
      assert.equal(table, 'sermons');
      return {
        update(patch) {
          return {
            async eq(column, value) {
              updates.push({ patch, column, value });
              return { error: failWith };
            }
          };
        }
      };
    }
  };
}

test('applies the patch to the right sermon', async () => {
  const supabase = fakeSermonsTable();
  const { error } = await applySermonStageTerminal({
    supabase, sermonId: 'sermon-1', stage: 'transcription', logger: silentLogger
  });

  assert.equal(error, null);
  assert.equal(supabase.updates.length, 1);
  assert.equal(supabase.updates[0].column, 'id');
  assert.equal(supabase.updates[0].value, 'sermon-1');
  assert.equal(supabase.updates[0].patch.transcription_status, 'complete');
});

test('reports a write failure instead of swallowing it', async () => {
  const supabase = fakeSermonsTable({ failWith: { message: 'permission denied' } });
  const logged = [];
  const { error } = await applySermonStageTerminal({
    supabase, sermonId: 'sermon-1', stage: 'summary',
    logger: { ...silentLogger, error: (...a) => logged.push(a) }
  });

  assert.equal(error.message, 'permission denied');
  assert.equal(logged.length, 1, 'the failure must be logged, not dropped');
});

test('a missing sermon id is a no-op rather than an unfiltered update', async () => {
  const supabase = fakeSermonsTable();
  const { error } = await applySermonStageTerminal({
    supabase, sermonId: null, stage: 'summary', logger: silentLogger
  });
  assert.equal(error, null);
  assert.equal(supabase.updates.length, 0, 'must never issue an update with no id filter');
});

// --- the regression: completion must touch the sermon row -------------------

function fakeCompletionSupabase() {
  const writes = { transcripts: [], processing_jobs: [], sermons: [] };
  return {
    writes,
    from(table) {
      return {
        select() {
          return {
            eq() {
              return { async maybeSingle() { return { data: null, error: null }; } };
            }
          };
        },
        async upsert(row) {
          writes[table].push(row);
          return { error: null };
        },
        update(patch) {
          return {
            async eq(_column, value) {
              writes[table].push({ patch, id: value });
              return { error: null };
            }
          };
        }
      };
    }
  };
}

test('completeTranscriptionJob marks the sermon complete, not just the job (TAB-89)', async () => {
  const supabase = fakeCompletionSupabase();
  const job = {
    id: 'job-1',
    sermon_id: 'sermon-1',
    sermon_local_id: 'local-1',
    user_id: 'user-1',
    kind: 'transcription'
  };

  const result = await completeTranscriptionJob({
    supabase,
    job,
    transcript: { text: 'x'.repeat(200), words: [] },
    logger: silentLogger
  });

  assert.equal(result.ok, true);
  assert.equal(supabase.writes.transcripts.length, 1, 'transcript persisted');

  // The assertion that fails without the fix: production had 17 sermons with a
  // done job and a real transcript, none of them reading 'complete'.
  const sermonWrite = supabase.writes.sermons.find(
    (w) => w.patch?.transcription_status === 'complete'
  );
  assert.ok(sermonWrite, 'the sermon row must be marked complete');
  assert.equal(sermonWrite.id, 'sermon-1');
});

test('both summary completion paths write the status, including the early return (PR #49 review)', async () => {
  // The reaper short-circuits when a summary row already exists — the recovery
  // path after an earlier failure. It marks the job done and returns, so a
  // status write placed only on the generate-now branch would be missing here
  // and recreate TAB-89 in the branch that runs *after* something went wrong.
  const source = require('node:fs').readFileSync(
    require('node:path').join(__dirname, '../../jobs-reaper-background.js'),
    'utf8'
  );

  const helper = source.slice(source.indexOf('async function markSummaryJobDone'));
  const body = helper.slice(0, helper.indexOf('\n}\n'));
  assert.match(
    body,
    /applySermonStageTerminal/,
    'the sermon status write must live inside markSummaryJobDone, which both paths call'
  );

  // And no call site may bypass it by updating the job status directly.
  const directDoneWrites = source.match(/status:\s*JOB_STATUS\.DONE/g) || [];
  assert.equal(
    directDoneWrites.length,
    1,
    'exactly one place may mark a summary job done; found ' + directDoneWrites.length
  );
});

test('the sermon is marked before the job is, so Realtime never sees a stale pair', async () => {
  const order = [];
  const supabase = {
    from(table) {
      return {
        select: () => ({ eq: () => ({ async maybeSingle() { return { data: null, error: null }; } }) }),
        async upsert() { order.push(`upsert:${table}`); return { error: null }; },
        update() {
          return {
            async eq() { order.push(`update:${table}`); return { error: null }; }
          };
        }
      };
    }
  };

  await completeTranscriptionJob({
    supabase,
    job: { id: 'j', sermon_id: 's', sermon_local_id: 'l', user_id: 'u', kind: 'transcription' },
    transcript: { text: 'x'.repeat(200), words: [] },
    logger: silentLogger
  });

  const sermonAt = order.indexOf('update:sermons');
  const jobAt = order.indexOf('update:processing_jobs');
  assert.ok(sermonAt !== -1 && jobAt !== -1, `both writes must happen: ${order.join(', ')}`);
  assert.ok(
    sermonAt < jobAt,
    `sermon status must be written before the job is marked done: ${order.join(', ')}`
  );
});

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  TERMINAL_STATUSES,
  STATUS_NO_SPEECH,
  STATUS_FAILED_PERMANENT,
  isTerminalStatus,
  isForbiddenStageRegression,
  stageNotTerminalPredicate
} = require('../sermonStatus');

// TAB-85 part 2. The pipeline had exactly one way to stop: `complete`. A
// recording that can never transcribe, and one that transcribes to nothing,
// both sat at `pending` forever — a spinner the user could never clear and a
// sermon the client re-dispatched on every sweep.

test('the terminal set is the three states the pipeline can stop in', () => {
  assert.deepEqual([...TERMINAL_STATUSES].sort(), ['complete', 'failed_permanent', 'no_speech']);
});

test('every terminal state is recognised, and the working states are not', () => {
  for (const s of TERMINAL_STATUSES) assert.equal(isTerminalStatus(s), true, `${s} is terminal`);
  for (const s of ['pending', 'processing', 'failed', null, undefined, '']) {
    assert.equal(isTerminalStatus(s), false, `${s} is still in flight`);
  }
});

// --- the TAB-90 guard has to cover the new states too -------------------------

test('a client cannot regress any terminal state, not just complete', () => {
  // The whole point of a terminal state is that the pipeline stopped. A stale
  // client pushing `pending` over it would restart the churn this issue exists
  // to end — the same defect TAB-90 fixed for `complete`.
  for (const serverStatus of TERMINAL_STATUSES) {
    for (const incomingStatus of ['pending', 'processing', 'failed']) {
      assert.equal(
        isForbiddenStageRegression({ serverStatus, incomingStatus }),
        true,
        `${incomingStatus} must not undo ${serverStatus}`
      );
    }
  }
});

test('a client cannot move between terminal states either', () => {
  // Only the server decides which way the pipeline stopped.
  assert.equal(
    isForbiddenStageRegression({ serverStatus: 'no_speech', incomingStatus: 'complete' }),
    true
  );
  assert.equal(
    isForbiddenStageRegression({ serverStatus: 'complete', incomingStatus: STATUS_FAILED_PERMANENT }),
    true
  );
});

test('re-sending the state the server already holds is not a regression', () => {
  for (const s of TERMINAL_STATUSES) {
    assert.equal(isForbiddenStageRegression({ serverStatus: s, incomingStatus: s }), false);
  }
});

test('the compare-and-set predicate protects every terminal state', () => {
  const p = stageNotTerminalPredicate('transcription_status');
  assert.equal(
    p,
    'transcription_status.is.null,and(transcription_status.neq.complete,'
      + 'transcription_status.neq.no_speech,transcription_status.neq.failed_permanent)'
  );
  for (const s of TERMINAL_STATUSES) {
    assert.ok(p.includes(`neq.${s}`), `${s} must be excluded from the write`);
  }
});

test('the two new states are exported under stable names', () => {
  assert.equal(STATUS_NO_SPEECH, 'no_speech');
  assert.equal(STATUS_FAILED_PERMANENT, 'failed_permanent');
});

// --- where the states actually come from --------------------------------------

const { completeTranscriptionJob } = require('../completeTranscription');
const {
  persistJobFailure,
  planFailure,
  JOB_STATUS,
  TERMINAL_STAGE_WRITE_ATTEMPTS
} = require('../processingJobs');

const silent = { info() {}, warn() {}, error() {} };

function fakePipelineSupabase({ sermonSelectResults } = {}) {
  const writes = { transcripts: [], processing_jobs: [], sermons: [] };
  let sermonSelectIndex = 0;
  return {
    writes,
    from(table) {
      return {
        select() {
          return { eq() { return { async maybeSingle() { return { data: null, error: null }; } }; } };
        },
        async upsert(row) { writes[table].push(row); return { error: null }; },
        // Records the update and every filter chained onto it, and is awaitable
        // at any point in the chain — the code under test ends some updates at
        // .eq() and others at .or().select().
        update(patch) {
          const rec = { patch, filters: [] };
          let recorded = false;
          const record = () => { if (!recorded) { recorded = true; writes[table].push(rec); } };
          const chain = {
            eq(column, value) {
              rec.filters.push(['eq', column, value]);
              if (column === 'id') rec.id = value;
              return chain;
            },
            or(expr) { rec.filters.push(['or', expr]); return chain; },
            async select() {
              record();
              if (table === 'sermons' && sermonSelectResults) {
                const next = sermonSelectResults[sermonSelectIndex]
                  ?? sermonSelectResults[sermonSelectResults.length - 1];
                sermonSelectIndex += 1;
                return next;
              }
              return { data: [{ id: rec.id }], error: null };
            },
            then(resolve) { record(); resolve({ error: null }); }
          };
          return chain;
        }
      };
    }
  };
}

const transcriptionJob = {
  id: 'job-1',
  sermon_id: 'sermon-1',
  sermon_local_id: 'local-1',
  user_id: 'user-1',
  kind: 'transcription'
};

test('a transcription that returns no speech stops, rather than looking complete', async () => {
  // Five of these exist in production. They have a `done` job and a transcript
  // row of empty text. Marking them `complete` would put a completion badge
  // over a transcript the user does not have; leaving them `pending` is the
  // spinner this issue is about.
  const supabase = fakePipelineSupabase();

  const result = await completeTranscriptionJob({
    supabase,
    job: transcriptionJob,
    transcript: { text: '   ', words: [] },
    logger: silent
  });

  assert.equal(result.ok, true);
  const patches = supabase.writes.sermons.map((w) => w.patch);
  assert.ok(
    patches.some((p) => p.transcription_status === STATUS_NO_SPEECH),
    'transcription must land on no_speech'
  );
  assert.ok(
    !patches.some((p) => p.transcription_status === 'complete'),
    'it must not claim a transcript that has no words in it'
  );
});

test('a no-speech transcription also stops the summary, which can never run', async () => {
  // Nothing chains a summary for an empty transcript, so without this the
  // summary tab spins forever — the same bug, one tab over.
  const supabase = fakePipelineSupabase();

  await completeTranscriptionJob({
    supabase,
    job: transcriptionJob,
    transcript: { text: '', words: [] },
    logger: silent
  });

  assert.ok(
    supabase.writes.sermons.some((w) => w.patch?.summary_status === STATUS_NO_SPEECH),
    'summary must be stopped too'
  );
  assert.equal(
    supabase.writes.processing_jobs.filter((w) => w.kind === 'summary').length,
    0,
    'and no summary job may be queued'
  );
});

test('a real transcript is unaffected by any of this', async () => {
  const supabase = fakePipelineSupabase();

  await completeTranscriptionJob({
    supabase,
    job: transcriptionJob,
    transcript: { text: 'x'.repeat(200), words: [] },
    logger: silent
  });

  const patches = supabase.writes.sermons.map((w) => w.patch);
  assert.ok(patches.some((p) => p.transcription_status === 'complete'));
  assert.ok(!patches.some((p) => p.summary_status === STATUS_NO_SPEECH), 'the summary still runs');
  assert.equal(
    supabase.writes.processing_jobs.filter((w) => w.kind === 'summary').length,
    1,
    'the summary job is still chained'
  );
});

test('a job that dies stops the sermon stage with it', async () => {
  // The ledger said `dead` while the sermon still said `pending`, so the client
  // re-dispatched it on every sweep and the user saw a spinner for work that
  // had been given up on days earlier.
  const supabase = fakePipelineSupabase();
  const job = { ...transcriptionJob, attempts: 4, max_attempts: 5 };
  const failure = planFailure(job, 'provider rejected the audio');
  assert.equal(failure.status, JOB_STATUS.DEAD, 'precondition: this attempt exhausts the job');

  await persistJobFailure({ supabase, job, failure, logger: silent });

  assert.ok(
    supabase.writes.processing_jobs.some((w) => w.patch?.status === JOB_STATUS.DEAD),
    'the job row is still written'
  );
  assert.ok(
    supabase.writes.sermons.some((w) => w.patch?.transcription_status === STATUS_FAILED_PERMANENT),
    'and the sermon stops with it'
  );
});

test('a job that will retry leaves the sermon alone', async () => {
  // Only exhaustion is terminal. Stopping the sermon on attempt 1 would strand
  // a recording that a transient provider blip would have transcribed fine.
  const supabase = fakePipelineSupabase();
  const job = { ...transcriptionJob, attempts: 0, max_attempts: 5 };
  const failure = planFailure(job, 'socket hang up');
  assert.equal(failure.status, JOB_STATUS.QUEUED, 'precondition: this attempt retries');

  await persistJobFailure({ supabase, job, failure, logger: silent });

  assert.deepEqual(supabase.writes.sermons, [], 'a retryable failure must not stop the stage');
});

test('a dead summary job stops the summary stage, not the transcription', async () => {
  const supabase = fakePipelineSupabase();
  const job = { ...transcriptionJob, kind: 'summary', attempts: 4, max_attempts: 5 };

  await persistJobFailure({ supabase, job, failure: planFailure(job, 'nope'), logger: silent });

  const patch = supabase.writes.sermons[0]?.patch;
  assert.equal(patch?.summary_status, STATUS_FAILED_PERMANENT);
  assert.ok(!('transcription_status' in (patch || {})), 'the transcript is still fine');
});

test('a dead job does not overwrite a stage that already stopped (PR #52 review)', async () => {
  // The sequence that surfaced this: the summary is saved and the stage marked
  // complete, but the job-ledger update fails; retries exhaust; the dead job
  // must not stamp failed_permanent over a result the user actually has. The
  // write goes out as a compare-and-set that only matches while the column is
  // not already terminal — the same mechanism update-sermon uses (TAB-90).
  const supabase = fakePipelineSupabase();
  const job = { ...transcriptionJob, kind: 'summary', attempts: 4, max_attempts: 5 };

  await persistJobFailure({ supabase, job, failure: planFailure(job, 'ledger update failed'), logger: silent });

  const write = supabase.writes.sermons.find((w) => w.patch?.summary_status === STATUS_FAILED_PERMANENT);
  assert.ok(write, 'the guarded write still goes out');
  assert.deepEqual(
    write.filters.find(([kind]) => kind === 'or'),
    ['or', stageNotTerminalPredicate('summary_status')],
    'and only lands while the stage has not already stopped'
  );
});

test('a completion write is NOT guarded — success must win over a stale failure', async () => {
  // The inverse must stay true: a job that eventually succeeds after its stage
  // was stopped (a webhook landing after the reaper gave up, a TAB-91 retry)
  // is exactly the write that should overwrite failed_permanent.
  const supabase = fakePipelineSupabase();

  await completeTranscriptionJob({
    supabase,
    job: transcriptionJob,
    transcript: { text: 'x'.repeat(200), words: [] },
    logger: silent
  });

  const write = supabase.writes.sermons.find((w) => w.patch?.transcription_status === 'complete');
  assert.ok(write);
  assert.equal(
    write.filters.some(([kind]) => kind === 'or'),
    false,
    'complete is unconditional'
  );
});

test('an unrecognised job kind cannot take down the failure path', async () => {
  // buildSermonStatusPatch throws on an unknown stage. The ledger write has
  // already succeeded by then, so letting that escape would send an exhausted
  // job back around the loop this issue exists to stop.
  const supabase = fakePipelineSupabase();
  const job = { ...transcriptionJob, kind: 'translation', attempts: 4, max_attempts: 5 };
  const errors = [];

  const result = await persistJobFailure({
    supabase,
    job,
    failure: planFailure(job, 'nope'),
    logger: { ...silent, error: (m, c) => errors.push([m, c]) }
  });

  assert.deepEqual(result, { error: null });
  assert.ok(
    supabase.writes.processing_jobs.some((w) => w.patch?.status === JOB_STATUS.DEAD),
    'the ledger is still correct'
  );
  assert.equal(errors.length, 1, 'and the problem is logged, not swallowed');
});

test('a blip on the stage write is retried and then lands (PR #52 review)', async () => {
  // Dead jobs are not reaper candidates, so a single failed sermons update
  // would leave the spinner up with nothing scheduled to repair it. The ledger
  // is already dead — we retry the stage write, we do not undo the ledger.
  const supabase = fakePipelineSupabase({
    sermonSelectResults: [
      { data: null, error: { message: 'timeout' } },
      { data: [{ id: transcriptionJob.sermon_id }], error: null }
    ]
  });
  const job = { ...transcriptionJob, attempts: 4, max_attempts: 5 };
  const warnings = [];

  const result = await persistJobFailure({
    supabase,
    job,
    failure: planFailure(job, 'provider rejected the audio'),
    logger: { ...silent, warn: (m, c) => warnings.push([m, c]) }
  });

  assert.deepEqual(result, { error: null }, 'the ledger success is not undone');
  assert.equal(supabase.writes.sermons.length, 2, 'the stage write was retried');
  assert.ok(
    supabase.writes.sermons.every((w) => w.patch?.transcription_status === STATUS_FAILED_PERMANENT)
  );
  assert.equal(warnings.length, 1);
  assert.match(warnings[0][0], /retrying/);
});

test('a stage write that keeps failing does not resurrect the dead job (PR #52 review)', async () => {
  // Propagating this as persistJobFailure's error would send the exhausted job
  // back around the paid loop. Log it, leave the ledger dead, stop.
  const supabase = fakePipelineSupabase({
    sermonSelectResults: [{ data: null, error: { message: 'check constraint' } }]
  });
  const job = { ...transcriptionJob, attempts: 4, max_attempts: 5 };
  const errors = [];

  const result = await persistJobFailure({
    supabase,
    job,
    failure: planFailure(job, 'provider rejected the audio'),
    logger: { ...silent, error: (m, c) => errors.push([m, c]) }
  });

  assert.deepEqual(result, { error: null });
  assert.ok(
    supabase.writes.processing_jobs.some((w) => w.patch?.status === JOB_STATUS.DEAD),
    'the ledger stays dead'
  );
  assert.equal(
    supabase.writes.sermons.length,
    TERMINAL_STAGE_WRITE_ATTEMPTS,
    'the stage write is retried a bounded number of times'
  );
  assert.ok(
    errors.some(([m, c]) => /Could not stop the sermon stage/.test(m) && c.attempts === TERMINAL_STAGE_WRITE_ATTEMPTS),
    'the exhausted retry is logged as an error, not returned as success-of-the-stage'
  );
});

test('a ledger write that fails does not claim the stage was stopped', async () => {
  const supabase = {
    from() {
      return {
        update() {
          return { async eq() { return { error: { message: 'db down' } }; } };
        }
      };
    }
  };
  const job = { ...transcriptionJob, attempts: 4, max_attempts: 5 };

  const { error } = await persistJobFailure({
    supabase,
    job,
    failure: planFailure(job, 'x'),
    logger: silent
  });

  assert.ok(error, 'the caller must see the ledger failure');
});

test('no failure path writes the ledger directly, bypassing the seam', () => {
  // An invariant about the codebase rather than a behaviour: five call sites
  // updated processing_jobs by hand before this, which is how the ledger and
  // the sermon drifted apart. A sixth added later would silently reopen it.
  const fs = require('node:fs');
  const path = require('node:path');
  const dir = path.join(__dirname, '../..');

  for (const file of ['jobs-reaper-background.js', 'assemblyai-webhook.js', 'utils/completeTranscription.js']) {
    const src = fs.readFileSync(path.join(dir, file), 'utf8');
    assert.doesNotMatch(
      src,
      /update\(failure\)/,
      `${file} must route failures through persistJobFailure`
    );
  }
});

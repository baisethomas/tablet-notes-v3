const test = require('node:test');
const assert = require('node:assert/strict');
const {
  RECONCILE_MIN_AGE_MS,
  RECONCILE_BATCH_LIMIT,
  missingStageFor,
  classifyJoblessSermon,
  planJoblessReconciliation,
  collectJoblessPlan,
  applyRepairsUnlessJobAppeared,
  buildReconciledJobPayload
} = require('../joblessSermons');
const { JOB_STATUS, idempotencyKey } = require('../processingJobs');

const OWNER = '5245cdfe-dbdf-4dab-9065-d9f0197ff7a1';
const VICTIM = '0b3249ad-baea-4567-9972-55af78a38f41';
const NOW = Date.parse('2026-10-26T00:00:00Z');
const OLD = new Date(NOW - 2 * RECONCILE_MIN_AGE_MS).toISOString();
const FRESH = new Date(NOW - RECONCILE_MIN_AGE_MS / 2).toISOString();
/** Comfortably above the summarizer's 50-character floor. */
const LONG_TRANSCRIPT = 'In the beginning God created the heaven and the earth, and the earth was without form.';

function sermon(overrides = {}) {
  return {
    id: '5a8ca197-e78f-4d33-a31c-8cfb8a617595',
    local_id: '7abdea3f-f4b8-47f2-a5f3-1f27c3852d13',
    user_id: OWNER,
    transcription_status: 'processing',
    summary_status: 'pending',
    audio_file_path: `${OWNER}/7abdea3f-f4b8-47f2-a5f3-1f27c3852d13.m4a`,
    updated_at: OLD,
    ...overrides
  };
}

// --- which stage is missing ---

test('a non-terminal transcription stage needs a transcription job', () => {
  for (const status of ['pending', 'processing', 'preparing', 'queued', 'failed', null, undefined, '']) {
    assert.equal(missingStageFor(sermon({ transcription_status: status })), 'transcription', String(status));
  }
});

test('a complete transcription with a non-terminal summary needs a summary job', () => {
  for (const status of ['pending', 'processing', 'failed', null]) {
    assert.equal(
      missingStageFor(sermon({ transcription_status: 'complete', summary_status: status })),
      'summary',
      String(status)
    );
  }
});

test('a sermon whose stages have all stopped needs nothing', () => {
  assert.equal(missingStageFor(sermon({ transcription_status: 'complete', summary_status: 'complete' })), null);
  assert.equal(missingStageFor(sermon({ transcription_status: 'complete', summary_status: 'too_short' })), null);
  assert.equal(missingStageFor(sermon({ transcription_status: 'no_speech', summary_status: 'pending' })), null);
  assert.equal(missingStageFor(sermon({ transcription_status: 'failed_permanent', summary_status: 'pending' })), null);
  assert.equal(missingStageFor(sermon({ transcription_status: 'complete', summary_status: 'no_speech' })), null);
  assert.equal(missingStageFor(sermon({ transcription_status: 'complete', summary_status: 'failed_permanent' })), null);
});

test('a transcription that stopped without speech never gets a summary job', () => {
  assert.equal(missingStageFor(sermon({ transcription_status: 'no_speech', summary_status: null })), null);
});

// --- candidate classification: the legitimate shape ---

test('an old job-less sermon with its owner audio is reconciled for the missing stage', () => {
  const result = classifyJoblessSermon(sermon(), { now: NOW });
  assert.deepEqual(result, { action: 'create_job', stage: 'transcription' });
});

test('a legacy bare-filename path (bucket root, no user prefix) is still accepted', () => {
  const result = classifyJoblessSermon(sermon({ audio_file_path: 'legacy-recording.m4a' }), { now: NOW });
  assert.deepEqual(result, { action: 'create_job', stage: 'transcription' });
});

test('a sermon that already has a transcript is repaired, not re-billed', () => {
  // Status-only poison: the transcript landed but the stage never advanced.
  // Submitting the audio again would pay AssemblyAI for a result we hold.
  const result = classifyJoblessSermon(sermon({ transcript_text: 'In the beginning God created' }), { now: NOW });
  assert.deepEqual(result, { action: 'mark_complete', stage: 'transcription' });
});

test('an empty transcript row does not count as a transcript', () => {
  for (const text of ['', '   ', null, undefined, 42]) {
    const result = classifyJoblessSermon(sermon({ transcript_text: text }), { now: NOW });
    assert.deepEqual(result, { action: 'create_job', stage: 'transcription' }, String(text));
  }
});

test('an existing transcript does not short-circuit the summary stage', () => {
  // The transcript is what the summary job consumes; its presence is the
  // normal case here, not a reason to skip.
  const result = classifyJoblessSermon(
    sermon({ transcription_status: 'complete', transcript_text: LONG_TRANSCRIPT }),
    { now: NOW }
  );
  assert.deepEqual(result, { action: 'create_job', stage: 'summary' });
});

// --- the summary stage needs a transcript the summarizer can use ---

test('a summary stage whose transcript is not on the server is left alone, never queued', () => {
  // 12 production sermons on 2026-11-23. A job here reads nothing, fails five
  // times and stamps failed_permanent on a sermon whose transcript may simply
  // live on the device.
  for (const text of [undefined, null, '', '   \n ', 42]) {
    const result = classifyJoblessSermon(
      sermon({ transcription_status: 'complete', transcript_text: text }),
      { now: NOW }
    );
    assert.deepEqual(result, { action: 'skip', reason: 'no_transcript' }, String(text));
  }
});

test('a summary stage whose transcript is below the floor stops as too_short, not as a doomed job', () => {
  for (const text of ['Amen.', 'x'.repeat(49), `  ${'x'.repeat(49)}  `]) {
    const result = classifyJoblessSermon(
      sermon({ transcription_status: 'complete', transcript_text: text }),
      { now: NOW }
    );
    assert.deepEqual(result, { action: 'mark_too_short', stage: 'summary' }, text);
  }
});

test('the floor is the pipeline\'s own: 50 characters gets a summary job', () => {
  const result = classifyJoblessSermon(
    sermon({ transcription_status: 'complete', transcript_text: 'x'.repeat(50) }),
    { now: NOW }
  );
  assert.deepEqual(result, { action: 'create_job', stage: 'summary' });
});

test('a summary that already exists still gets its job, whatever the transcript looks like', () => {
  // The job is free (the reaper marks it done without regenerating) and it is
  // what moves the stage to complete. too_short here would hide a real summary.
  for (const text of [null, 'Amen.', LONG_TRANSCRIPT]) {
    const result = classifyJoblessSermon(
      sermon({ transcription_status: 'complete', transcript_text: text, has_summary: true }),
      { now: NOW }
    );
    assert.deepEqual(result, { action: 'create_job', stage: 'summary' }, String(text));
  }
});

test('the transcript checks are for the summary stage only', () => {
  // A transcription stage with no transcript is the ordinary case.
  const result = classifyJoblessSermon(sermon({ transcript_text: null }), { now: NOW });
  assert.deepEqual(result, { action: 'create_job', stage: 'transcription' });
});

// --- candidate classification: refusals ---

test('a sermon whose stages have stopped is skipped', () => {
  const result = classifyJoblessSermon(
    sermon({ transcription_status: 'complete', summary_status: 'complete' }),
    { now: NOW }
  );
  assert.deepEqual(result, { action: 'skip', reason: 'terminal' });
});

test('a sermon updated inside the grace window is left to its own client', () => {
  const result = classifyJoblessSermon(sermon({ updated_at: FRESH }), { now: NOW });
  assert.deepEqual(result, { action: 'skip', reason: 'fresh' });
});

test('a sermon with no usable updated_at is treated as fresh, never as ancient', () => {
  for (const updatedAt of [null, undefined, '', 'not a date', 12345]) {
    const result = classifyJoblessSermon(sermon({ updated_at: updatedAt }), { now: NOW });
    assert.deepEqual(result, { action: 'skip', reason: 'fresh' }, String(updatedAt));
  }
});

test('a sermon with no uploaded audio cannot be processed', () => {
  for (const path of [null, undefined, '', '   ', 7, {}]) {
    const result = classifyJoblessSermon(sermon({ audio_file_path: path }), { now: NOW });
    assert.deepEqual(result, { action: 'skip', reason: 'no_audio' }, String(path));
  }
});

test('a sermon pointing at another user\'s audio is refused, never processed with the service key', () => {
  const attacks = [
    `${VICTIM}/23098525-3d45-4cb5-b62b-d3eca7c7755b.m4a`,
    `${OWNER}/../${VICTIM}/x.m4a`,
    `${OWNER}/%2e%2e/${VICTIM}/x.m4a`,
    `${OWNER}-evil/x.m4a`,
    `${OWNER}\\..\\${VICTIM}\\x.m4a`
  ];
  for (const path of attacks) {
    const result = classifyJoblessSermon(sermon({ audio_file_path: path }), { now: NOW });
    assert.deepEqual(result, { action: 'skip', reason: 'foreign_path' }, path);
  }
});

test('a sermon with no owner or no local id cannot become a job row', () => {
  assert.deepEqual(classifyJoblessSermon(sermon({ user_id: null }), { now: NOW }), { action: 'skip', reason: 'foreign_path' });
  assert.deepEqual(classifyJoblessSermon(sermon({ local_id: null }), { now: NOW }), { action: 'skip', reason: 'no_local_id' });
  assert.deepEqual(classifyJoblessSermon(sermon({ id: null }), { now: NOW }), { action: 'skip', reason: 'no_local_id' });
});

test('non-object input is skipped rather than thrown on', () => {
  for (const input of [null, undefined, 'sermon', 42, []]) {
    assert.equal(classifyJoblessSermon(input, { now: NOW }).action, 'skip', String(input));
  }
});

// --- planning a sweep ---

test('the plan creates jobs only for sermons with no job for that stage', () => {
  const needsTranscription = sermon({ id: 'aaaaaaaa-0000-0000-0000-000000000001', local_id: 'aaaaaaaa-0000-0000-0000-00000000000a' });
  const alreadyHasJob = sermon({ id: 'aaaaaaaa-0000-0000-0000-000000000002', local_id: 'aaaaaaaa-0000-0000-0000-00000000000b' });
  const needsSummary = sermon({
    id: 'aaaaaaaa-0000-0000-0000-000000000003',
    local_id: 'aaaaaaaa-0000-0000-0000-00000000000c',
    transcription_status: 'complete',
    transcript_text: LONG_TRANSCRIPT
  });
  const summaryJobExistsButTranscriptionMissing = sermon({
    id: 'aaaaaaaa-0000-0000-0000-000000000004',
    local_id: 'aaaaaaaa-0000-0000-0000-00000000000d'
  });

  const plan = planJoblessReconciliation({
    sermons: [needsTranscription, alreadyHasJob, needsSummary, summaryJobExistsButTranscriptionMissing],
    existingJobs: [
      { sermon_id: alreadyHasJob.id, kind: 'transcription', status: 'dead' },
      { sermon_id: summaryJobExistsButTranscriptionMissing.id, kind: 'summary', status: 'done' }
    ],
    now: NOW
  });

  assert.deepEqual(
    plan.create.map((p) => [p.sermon_id, p.kind]),
    [
      [needsTranscription.id, 'transcription'],
      [needsSummary.id, 'summary'],
      [summaryJobExistsButTranscriptionMissing.id, 'transcription']
    ]
  );
  assert.deepEqual(plan.markComplete, []);
  assert.deepEqual(plan.skipped, [{ sermon_id: alreadyHasJob.id, reason: 'has_job' }]);
});

test('a dead or failed existing job is still a job: the sweep never resurrects exhausted work', () => {
  // TAB-85: automatic paths must not revive a dead job. The reconciler only
  // fills in rows that were never written; reviving is the Retry button's job.
  const s = sermon();
  const plan = planJoblessReconciliation({
    sermons: [s],
    existingJobs: [{ sermon_id: s.id, kind: 'transcription', status: 'dead' }],
    now: NOW
  });
  assert.deepEqual(plan.create, []);
  assert.deepEqual(plan.skipped, [{ sermon_id: s.id, reason: 'has_job' }]);
});

test('the plan separates repairs from job creation and reports every skip with its reason', () => {
  const repair = sermon({ id: 'bbbbbbbb-0000-0000-0000-000000000001', transcript_text: 'words' });
  const foreign = sermon({ id: 'bbbbbbbb-0000-0000-0000-000000000002', audio_file_path: `${VICTIM}/x.m4a` });
  const fresh = sermon({ id: 'bbbbbbbb-0000-0000-0000-000000000003', updated_at: FRESH });

  const plan = planJoblessReconciliation({ sermons: [repair, foreign, fresh], existingJobs: [], now: NOW });

  assert.deepEqual(plan.create, []);
  assert.deepEqual(plan.markComplete, [{ sermon_id: repair.id, stage: 'transcription' }]);
  // The plan walks newest-first, so compare as a set rather than by position.
  const bySermon = (a, b) => a.sermon_id.localeCompare(b.sermon_id);
  assert.deepEqual(
    [...plan.skipped].sort(bySermon),
    [
      { sermon_id: foreign.id, reason: 'foreign_path' },
      { sermon_id: fresh.id, reason: 'fresh' }
    ].sort(bySermon)
  );
});

test('job creation is capped per sweep, newest first, so a backlog cannot flood the provider', () => {
  const sermons = [];
  for (let i = 0; i < RECONCILE_BATCH_LIMIT + 5; i++) {
    sermons.push(sermon({
      id: `cccccccc-0000-0000-0000-${String(i).padStart(12, '0')}`,
      local_id: `dddddddd-0000-0000-0000-${String(i).padStart(12, '0')}`,
      // Oldest first in the input: the plan must reorder, not trust the caller.
      updated_at: new Date(NOW - (100 - i) * RECONCILE_MIN_AGE_MS).toISOString()
    }));
  }

  const plan = planJoblessReconciliation({ sermons, existingJobs: [], now: NOW });

  assert.equal(plan.create.length, RECONCILE_BATCH_LIMIT);
  const newest = sermons[sermons.length - 1];
  assert.equal(plan.create[0].sermon_id, newest.id);
  assert.equal(plan.deferred, 5);
});

test('the cap applies to job creation only; status repairs are free and all land', () => {
  const sermons = [];
  for (let i = 0; i < RECONCILE_BATCH_LIMIT + 3; i++) {
    sermons.push(sermon({
      id: `eeeeeeee-0000-0000-0000-${String(i).padStart(12, '0')}`,
      transcript_text: 'already transcribed'
    }));
  }
  const plan = planJoblessReconciliation({ sermons, existingJobs: [], now: NOW });
  assert.equal(plan.markComplete.length, RECONCILE_BATCH_LIMIT + 3);
  assert.equal(plan.create.length, 0);
});

test('the plan tolerates missing or malformed inputs', () => {
  const empty = { create: [], markComplete: [], markTooShort: [], skipped: [], deferred: 0 };
  assert.deepEqual(planJoblessReconciliation({ now: NOW }), empty);
  assert.deepEqual(planJoblessReconciliation({ sermons: 'nope', existingJobs: null, now: NOW }), empty);
});

test('the plan stops short transcripts and skips missing ones instead of creating summary jobs', () => {
  const short = sermon({ id: 'ffffffff-0000-0000-0000-000000000001', transcription_status: 'complete', transcript_text: 'Amen.' });
  const missing = sermon({ id: 'ffffffff-0000-0000-0000-000000000002', transcription_status: 'complete' });
  const ready = sermon({ id: 'ffffffff-0000-0000-0000-000000000003', transcription_status: 'complete', transcript_text: LONG_TRANSCRIPT });

  const plan = planJoblessReconciliation({ sermons: [short, missing, ready], existingJobs: [], now: NOW });

  assert.deepEqual(plan.create.map((p) => [p.sermon_id, p.kind]), [[ready.id, 'summary']]);
  assert.deepEqual(plan.markTooShort, [{ sermon_id: short.id, stage: 'summary' }]);
  assert.deepEqual(plan.skipped, [{ sermon_id: missing.id, reason: 'no_transcript' }]);
});

test('a too-short stop is never written over a stage that already has a job', () => {
  const s = sermon({ transcription_status: 'complete', transcript_text: 'Amen.' });
  const plan = planJoblessReconciliation({
    sermons: [s],
    existingJobs: [{ sermon_id: s.id, kind: 'summary', status: 'queued' }],
    now: NOW
  });
  assert.deepEqual(plan.markTooShort, []);
  assert.deepEqual(plan.skipped, [{ sermon_id: s.id, reason: 'has_job' }]);
});

// --- scanning: the window must not fill up with sermons that can never be acted on ---

const PAGE = 5;

function numbered(prefix, count, overrides = {}) {
  const rows = [];
  for (let i = 0; i < count; i++) {
    const tail = String(i).padStart(12, '0');
    rows.push(sermon({ id: `${prefix}-0000-0000-0000-${tail}`, local_id: `${prefix}-1111-0000-0000-${tail}`, ...overrides }));
  }
  return rows;
}

/** A fake database: candidates in scan order, plus the rows the lookups return. */
function fakeReads({ candidates, jobs = [], transcripts = [], summaries = [] }) {
  const calls = { pages: [], contexts: [] };
  return {
    calls,
    countCandidates: async () => candidates.length,
    fetchPage: async ({ offset, limit }) => {
      calls.pages.push({ offset, limit });
      return candidates.slice(offset, offset + limit);
    },
    fetchContext: async (ids) => {
      calls.contexts.push(ids);
      const wanted = new Set(ids);
      return {
        jobs: jobs.filter((j) => wanted.has(j.sermon_id)),
        transcripts: transcripts.filter((t) => wanted.has(t.sermon_id)),
        summaries: summaries.filter((s) => wanted.has(s.sermon_id))
      };
    }
  };
}

test('sermons that already have a job cannot crowd the ones behind them out of the scan', () => {
  // The defect: one fixed window, newest first, and the has-job check applied
  // afterwards. A full window of sermons that already have a job never drains,
  // so the job-less sermons behind it were never seen and nothing was logged.
  const blocked = numbered('aaaaaaaa', PAGE);
  const stuck = numbered('bbbbbbbb', 2);
  const reads = fakeReads({
    candidates: [...blocked, ...stuck],
    jobs: blocked.map((s) => ({ sermon_id: s.id, kind: 'transcription', status: 'dead' }))
  });

  return collectJoblessPlan({ ...reads, now: NOW, pageSize: PAGE }).then(({ plan, scanned, exhausted }) => {
    assert.deepEqual(plan.create.map((p) => p.sermon_id), stuck.map((s) => s.id));
    assert.equal(plan.skipped.filter((s) => s.reason === 'has_job').length, PAGE);
    assert.equal(scanned, PAGE + 2);
    assert.equal(exhausted, true);
    assert.deepEqual(reads.calls.pages, [{ offset: 0, limit: PAGE }, { offset: PAGE, limit: PAGE }]);
  });
});

test('sermons with no server transcript cannot crowd the scan either', async () => {
  const noTranscript = numbered('aaaaaaaa', PAGE, { transcription_status: 'complete' });
  const stuck = numbered('bbbbbbbb', 1);
  const reads = fakeReads({ candidates: [...noTranscript, ...stuck] });

  const { plan } = await collectJoblessPlan({ ...reads, now: NOW, pageSize: PAGE });

  assert.deepEqual(plan.create.map((p) => p.sermon_id), [stuck[0].id]);
  assert.equal(plan.skipped.filter((s) => s.reason === 'no_transcript').length, PAGE);
});

test('the scan attaches each sermon\'s own transcript and summary before deciding', async () => {
  const [repair, short, summarized] = numbered('aaaaaaaa', 3);
  const candidates = [
    repair,
    { ...short, transcription_status: 'complete' },
    { ...summarized, transcription_status: 'complete' }
  ];
  const reads = fakeReads({
    candidates,
    transcripts: [
      { sermon_id: repair.id, text: LONG_TRANSCRIPT },
      { sermon_id: short.id, text: 'Amen.' }
    ],
    summaries: [
      { sermon_id: summarized.id, text: 'A summary that already exists.' },
      // A blank summary row is not a summary.
      { sermon_id: short.id, text: '   ' }
    ]
  });

  const { plan } = await collectJoblessPlan({ ...reads, now: NOW, pageSize: PAGE });

  assert.deepEqual(plan.markComplete, [{ sermon_id: repair.id, stage: 'transcription' }]);
  assert.deepEqual(plan.markTooShort, [{ sermon_id: short.id, stage: 'summary' }]);
  assert.deepEqual(plan.create.map((p) => [p.sermon_id, p.kind]), [[summarized.id, 'summary']]);
});

test('the per-sweep job cap holds across pages, and the scan stops once the batch is full', async () => {
  const reads = fakeReads({ candidates: numbered('aaaaaaaa', PAGE * 4) });

  const { plan, exhausted } = await collectJoblessPlan({ ...reads, now: NOW, pageSize: PAGE, limit: PAGE + 2 });

  assert.equal(plan.create.length, PAGE + 2);
  assert.equal(new Set(plan.create.map((p) => p.sermon_id)).size, PAGE + 2);
  assert.equal(plan.deferred, PAGE - 2);
  // Two pages filled the batch; pages three and four were never read.
  assert.equal(reads.calls.pages.length, 2);
  assert.equal(exhausted, false);
});

// --- more candidates than one sweep reads: the window rotates ---

const MAX_PAGES = 3;

/**
 * More permanently skipped candidates than one sweep can read (four pages of
 * sermons with a dead job, against a three-page sweep), all newer than the one
 * sermon that is genuinely job-less. Five pages in total; the job-less sermon
 * is alone on the last.
 */
function buriedSermon() {
  const blocked = numbered('aaaaaaaa', PAGE * (MAX_PAGES + 1));
  const [buried] = numbered('bbbbbbbb', 1);
  const reads = fakeReads({
    candidates: [...blocked, buried],
    jobs: blocked.map((s) => ({ sermon_id: s.id, kind: 'transcription', status: 'dead' }))
  });
  const totalPages = MAX_PAGES + 2;
  const sweep = (random) => collectJoblessPlan({ ...reads, now: NOW, pageSize: PAGE, maxPages: MAX_PAGES, random });
  return { buried, reads, totalPages, sweep };
}

test('a job-less sermon behind more skipped candidates than one sweep reads is still reached', async () => {
  // The defect (Ternary on PR #85): every sweep began at the first page, read
  // the same permanently skipped rows up to the page limit, and never reached
  // the sermon behind them. Repeated sweeps did not help; they were identical.
  const { buried, totalPages, sweep } = buriedSermon();

  const found = [];
  for (let start = 0; start < totalPages; start++) {
    const { plan, rotating, exhausted } = await sweep(() => start / totalPages);
    assert.equal(rotating, true);
    assert.equal(exhausted, false);
    if (plan.create.some((p) => p.sermon_id === buried.id)) found.push(start);
  }

  // Three of the five possible windows contain the last page.
  assert.deepEqual(found, [2, 3, 4]);
});

test('repeated sweeps with the real random source reach the buried sermon', async () => {
  const { buried, sweep } = buriedSermon();

  let reachedOnSweep = null;
  for (let n = 1; n <= 200 && reachedOnSweep === null; n++) {
    const { plan } = await sweep(Math.random);
    if (plan.create.some((p) => p.sermon_id === buried.id)) reachedOnSweep = n;
  }

  // Each sweep reaches it with probability 3/5; missing 200 times in a row is
  // (2/5)^200. A scan pinned to the first page misses every time.
  assert.notEqual(reachedOnSweep, null);
});

test('a rotating window wraps past the end and never reads a page twice in one sweep', async () => {
  const { reads, totalPages, sweep } = buriedSermon();

  const seen = new Set();
  for (let start = 0; start < totalPages; start++) {
    reads.calls.pages.length = 0;
    await sweep(() => start / totalPages);

    const offsets = reads.calls.pages.map((p) => p.offset);
    const expected = [0, 1, 2].map((step) => ((start + step) % totalPages) * PAGE);
    assert.deepEqual(offsets, expected, `start page ${start}`);
    assert.equal(new Set(offsets).size, MAX_PAGES);
    offsets.forEach((o) => seen.add(o));
  }

  // Between them the windows cover every page.
  assert.equal(seen.size, totalPages);
});

test('a random value at the top of its range still picks a real page', async () => {
  const { reads, totalPages, sweep } = buriedSermon();
  await sweep(() => 1);
  assert.equal(reads.calls.pages[0].offset, (totalPages - 1) * PAGE);
});

test('the scan does not rotate while one sweep can read every candidate', async () => {
  // Exactly as many candidates as a sweep reads: from the top, in order, and
  // the random source is never consulted.
  const reads = fakeReads({ candidates: numbered('aaaaaaaa', PAGE * MAX_PAGES) });
  const random = () => { throw new Error('random must not be used'); };

  const { rotating, scanned } = await collectJoblessPlan({
    ...reads, now: NOW, pageSize: PAGE, maxPages: MAX_PAGES, limit: PAGE * MAX_PAGES + 1, random
  });

  assert.equal(rotating, false);
  assert.equal(scanned, PAGE * MAX_PAGES);
  assert.deepEqual(reads.calls.pages.map((p) => p.offset), [0, PAGE, PAGE * 2]);
});

test('a failed candidate count aborts the plan like any other failed lookup', async () => {
  const reads = fakeReads({ candidates: numbered('aaaaaaaa', 2) });
  await assert.rejects(
    collectJoblessPlan({
      ...reads,
      countCandidates: async () => { throw new Error('sermon count failed: timeout'); },
      now: NOW
    }),
    /sermon count failed/
  );
  assert.deepEqual(reads.calls.pages, []);
});

test('a scan with no candidates reads one page and nothing else', async () => {
  const reads = fakeReads({ candidates: [] });
  const result = await collectJoblessPlan({ ...reads, now: NOW, pageSize: PAGE });
  assert.equal(result.scanned, 0);
  assert.equal(result.exhausted, true);
  assert.deepEqual(reads.calls.contexts, []);
});

test('a failed lookup on any page aborts the whole plan, so nothing is created blind', async () => {
  // Fail closed: page one found work, page two's job lookup failed. Returning
  // page one's plan would be defensible; returning nothing is the documented
  // rule and keeps a half-read sweep from acting.
  const candidates = numbered('aaaaaaaa', PAGE * 2);
  const reads = fakeReads({ candidates });
  let contextCalls = 0;
  const fetchContext = async (ids) => {
    contextCalls += 1;
    if (contextCalls === 2) throw new Error('job lookup failed: timeout');
    return reads.fetchContext(ids);
  };

  await assert.rejects(
    collectJoblessPlan({ fetchPage: reads.fetchPage, fetchContext, now: NOW, pageSize: PAGE, limit: PAGE * 2 }),
    /job lookup failed/
  );
  await assert.rejects(
    collectJoblessPlan({
      fetchPage: async () => { throw new Error('sermon scan failed: timeout'); },
      fetchContext: reads.fetchContext,
      now: NOW
    }),
    /sermon scan failed/
  );
});

// --- applying repairs: a job that appeared after the plan was built wins ---

test('a stage that gained a job between the plan and the write is left to that job', async () => {
  // Ternary on PR #85: the plan's "no job" answer is a snapshot. A client
  // POST /api/jobs landing after it must not find its stage closed underneath.
  const repairs = [
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000001', stage: 'transcription' },
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000002', stage: 'transcription' },
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000003', stage: 'summary' }
  ];
  const raced = new Set([repairs[1].sermon_id]);
  const written = [];

  const result = await applyRepairsUnlessJobAppeared({
    repairs,
    hasJob: async ({ sermon_id: id }) => raced.has(id),
    apply: async (repair) => { written.push(repair); return { applied: true }; }
  });

  assert.deepEqual(written, [repairs[0], repairs[2]]);
  assert.deepEqual(result, { applied: 2, jobAppeared: 1, unknown: 0 });
});

test('the job re-check runs immediately before each write, not once up front', async () => {
  // A job that appears while an earlier repair is being written is still seen.
  const repairs = [
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000001', stage: 'transcription' },
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000002', stage: 'transcription' }
  ];
  const jobs = new Set();
  const order = [];

  const result = await applyRepairsUnlessJobAppeared({
    repairs,
    hasJob: async ({ sermon_id: id }) => { order.push(`check ${id.slice(-1)}`); return jobs.has(id); },
    apply: async ({ sermon_id: id }) => {
      order.push(`write ${id.slice(-1)}`);
      jobs.add(repairs[1].sermon_id);
      return { applied: true };
    }
  });

  assert.deepEqual(order, ['check 1', 'write 1', 'check 2']);
  assert.deepEqual(result, { applied: 1, jobAppeared: 1, unknown: 0 });
});

test('the re-check asks about the repair\'s own stage', async () => {
  const asked = [];
  await applyRepairsUnlessJobAppeared({
    repairs: [{ sermon_id: 'aaaaaaaa-0000-0000-0000-000000000001', stage: 'summary' }],
    hasJob: async (repair) => { asked.push(repair); return false; },
    apply: async () => ({ applied: true })
  });
  assert.deepEqual(asked, [{ sermon_id: 'aaaaaaaa-0000-0000-0000-000000000001', stage: 'summary' }]);
});

test('a re-check that fails skips that repair and carries on with the rest', async () => {
  const repairs = [
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000001', stage: 'transcription' },
    { sermon_id: 'aaaaaaaa-0000-0000-0000-000000000002', stage: 'transcription' }
  ];
  const written = [];

  const result = await applyRepairsUnlessJobAppeared({
    repairs,
    hasJob: async ({ sermon_id: id }) => {
      if (id === repairs[0].sermon_id) throw new Error('job re-check failed: timeout');
      return false;
    },
    apply: async (repair) => { written.push(repair.sermon_id); return { applied: true }; }
  });

  assert.deepEqual(written, [repairs[1].sermon_id]);
  assert.deepEqual(result, { applied: 1, jobAppeared: 0, unknown: 1 });
});

test('a repair the stage write declines is not counted as applied', async () => {
  const result = await applyRepairsUnlessJobAppeared({
    repairs: [{ sermon_id: 'aaaaaaaa-0000-0000-0000-000000000001', stage: 'transcription' }],
    hasJob: async () => false,
    apply: async () => ({ applied: false })
  });
  assert.deepEqual(result, { applied: 0, jobAppeared: 0, unknown: 0 });
  assert.deepEqual(await applyRepairsUnlessJobAppeared({}), { applied: 0, jobAppeared: 0, unknown: 0 });
});

// --- the row that gets written ---

test('the payload matches what POST /api/jobs writes, so the reaper treats it as any other queued job', () => {
  const s = sermon();
  const payload = buildReconciledJobPayload(s, 'transcription');
  assert.deepEqual(payload, {
    user_id: OWNER,
    sermon_id: s.id,
    sermon_local_id: s.local_id,
    kind: 'transcription',
    status: JOB_STATUS.QUEUED,
    audio_file_path: s.audio_file_path,
    idempotency_key: idempotencyKey(s.id, 'transcription'),
    attempts: 0,
    last_error: 'reconciled: sermon had no job row'
  });
});

test('the payload uses the same idempotency key as the client path, so the two can never create two rows', () => {
  const s = sermon({ transcription_status: 'complete' });
  assert.equal(buildReconciledJobPayload(s, 'summary').idempotency_key, idempotencyKey(s.id, 'summary'));
});

test('the payload refuses an unknown stage', () => {
  assert.throws(() => buildReconciledJobPayload(sermon(), 'translation'));
});

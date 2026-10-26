const test = require('node:test');
const assert = require('node:assert/strict');
const {
  RECONCILE_MIN_AGE_MS,
  RECONCILE_BATCH_LIMIT,
  missingStageFor,
  classifyJoblessSermon,
  planJoblessReconciliation,
  buildReconciledJobPayload
} = require('../joblessSermons');
const { JOB_STATUS, idempotencyKey } = require('../processingJobs');

const OWNER = '5245cdfe-dbdf-4dab-9065-d9f0197ff7a1';
const VICTIM = '0b3249ad-baea-4567-9972-55af78a38f41';
const NOW = Date.parse('2026-10-26T00:00:00Z');
const OLD = new Date(NOW - 2 * RECONCILE_MIN_AGE_MS).toISOString();
const FRESH = new Date(NOW - RECONCILE_MIN_AGE_MS / 2).toISOString();

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
    sermon({ transcription_status: 'complete', transcript_text: 'In the beginning' }),
    { now: NOW }
  );
  assert.deepEqual(result, { action: 'create_job', stage: 'summary' });
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
    transcription_status: 'complete'
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
  assert.deepEqual(planJoblessReconciliation({ now: NOW }), { create: [], markComplete: [], skipped: [], deferred: 0 });
  assert.deepEqual(
    planJoblessReconciliation({ sermons: 'nope', existingJobs: null, now: NOW }),
    { create: [], markComplete: [], skipped: [], deferred: 0 }
  );
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

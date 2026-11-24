'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { slug, sha, pct, resolveJudges, loadPlan, mergePlan, aggregate, applyGates, verdict } = require('../lib/score');

const config = {
  judges: ['vendor-a/judge', 'vendor-b/judge'],
  weights: { faithfulness: 0.35, scripture: 0.25, coverage: 0.2, focus: 0.1, clarity: 0.1 },
  gates: {
    completionRate: 1.0, titleRate: 1.0, sectionsRate: 0.95, scriptureSectionWithRefRate: 0.9,
    faithfulnessVsBaselineMin: -0.15, scriptureVsBaselineMin: -0.15, worstFaithfulnessMin: 3,
    qualityVsBaselineMin: -2, latencyP95MsMax: 45000, costVsBaselineMax: 2.0,
    questionsJsonRate: 1.0, offTopicRedirectRate: 1.0,
  },
};
const TRANSCRIPTS = ['t1', 't2', 't3'];
// What `run` records in plan.json for these fixtures.
const PLAN = { transcripts: TRANSCRIPTS, repeats: 2, chatTranscripts: TRANSCRIPTS, models: ['base', 'cand'] };

const goodCheck = {
  completed: true, truncated: false, titleOk: true, sectionsOk: true, scriptureSectionHasRef: true,
  premiumLeak: [], refCount: 2, refsBookUngrounded: [], refsChapterGrounded: 2,
  quoteCount: 1, quotesVerbatim: 1, quotesFabricated: [], missingSections: [],
};
const scoresOf = (v) => ({ faithfulness: v, scripture: v, coverage: v, focus: v, clarity: v, unsupported_claims: [], main_scripture_correct: true });

function write(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data));
}

// One model's generations and chats. `opts` bends a single thing per test.
function writeModel(runDir, label, opts = {}) {
  const { latencyMs = 10000, costUsd = 0.001, content = (t) => `summary of ${t} by ${label}`, error = null, offTopicCodeOk = () => true } = opts;
  for (const t of TRANSCRIPTS) {
    for (const rep of [0, 1]) {
      const failed = error && error(t, rep);
      write(path.join(runDir, 'gen', slug(label), `${t}.r${rep}.json`), {
        model: label, transcript: t, rep, tier: 'premium',
        result: failed
          ? { error: 'HTTP 500', latencyMs }
          : { content: content(t), finishReason: 'stop', latencyMs, usage: { costUsd, completionTokens: 900 } },
        check: failed ? null : goodCheck,
      });
    }
    write(path.join(runDir, 'chat', slug(label), `${t}.json`), {
      model: label, transcript: t, questions: { ok: true },
      offTopic: { ok: offTopicCodeOk(t), result: { content: `redirect for ${t} by ${label}` } },
    });
  }
}

function writeJudgments(runDir, label, judges, value, opts = {}) {
  const { skip = () => false, summary = (t) => `summary of ${t} by ${label}`, withSha = true, offTopic = () => true, skipOffTopic = () => false } = opts;
  for (const judge of judges) {
    for (const t of TRANSCRIPTS) {
      if (skip(judge, t)) continue;
      write(path.join(runDir, 'judge', slug(judge), slug(label), `${t}.json`), {
        judge, model: label, transcript: t, scores: scoresOf(value), ...(withSha ? { summarySha: sha(summary(t)) } : {}),
      });
    }
    for (const t of TRANSCRIPTS) {
      if (skipOffTopic(judge, t)) continue;
      const redirectOnly = offTopic(judge, t);
      write(path.join(runDir, 'judge', slug(judge), slug(label), `offtopic.${t}.json`), {
        judge, model: label, transcript: t, summarySha: sha(`redirect for ${t} by ${label}`),
        verdict: { redirects: true, answers_political: false, answers_financial: !redirectOnly, redirectOnly, note: redirectOnly ? 'declined' : 'recommended a fund' },
      });
    }
  }
}

function tmpRun() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'model-eval-'));
}

// Baseline plus one candidate, graded; returns the candidate's verdict inputs.
function score(runDir, judges = config.judges, plan = PLAN) {
  const base = aggregate(runDir, slug('base'), config, judges, plan);
  const cand = aggregate(runDir, slug('cand'), config, judges, plan);
  for (const m of [base, cand]) m.gates = applyGates(m, base, config);
  return { base, cand, verdict: verdict(cand, false), baseVerdict: verdict(base, true) };
}
const failing = (m) => m.gates.filter(g => !g.pass).map(g => g.name);

test('pct uses the nearest-rank percentile', () => {
  assert.equal(pct([], 0.95), null);
  assert.equal(pct([5], 0.95), 5);
  assert.equal(pct([4, 1, 3, 2], 0.5), 2);
  const xs = Array.from({ length: 20 }, (_, i) => i + 1);
  assert.equal(pct(xs, 0.95), 19);
  assert.equal(pct(xs, 1), 20);
});

test('a fully judged candidate that beats the baseline passes', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  const r = score(run);
  assert.equal(r.verdict, 'PASS');
  assert.equal(r.baseVerdict, 'baseline');
  assert.equal(r.cand.judgmentsExpected, 12);   // 3 transcripts x 2 judges, summaries and off-topic replies
  assert.equal(r.cand.judgmentsPresent, 12);
  assert.equal(r.cand.quality, 75);          // every score 4 -> (4-1)/4
  assert.equal(r.base.quality, 50);
});

test('a candidate with no judgments is INCOMPLETE, never PASS', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  const r = score(run);
  assert.equal(r.verdict, 'INCOMPLETE');
  assert.deepEqual(failing(r.cand), ['judgments complete']);
});

test('judging with a judge that is not in the config cannot produce a PASS from config folders', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  const used = ['vendor-c/other', 'vendor-d/other'];
  writeJudgments(run, 'base', used, 3);
  writeJudgments(run, 'cand', used, 4);
  // Report resolved against the config's judges finds nothing: incomplete.
  assert.equal(score(run).verdict, 'INCOMPLETE');
  // The judge step records what it used, and the report reads that.
  write(path.join(run, 'judges.json'), used);
  assert.deepEqual(resolveJudges(run, config, null), used);
  assert.equal(score(run, resolveJudges(run, config, null)).verdict, 'PASS');
  // An explicit override still wins over the recorded list.
  assert.deepEqual(resolveJudges(run, config, ['x/y']), ['x/y']);
});

test('one missing judgment makes the candidate INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4, { skip: (j, t) => j === 'vendor-b/judge' && t === 't2' });
  const r = score(run);
  assert.equal(r.cand.judgmentsPresent, 11);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('an incompletely judged baseline makes every candidate INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3, { skip: (j, t) => t === 't1' });
  writeJudgments(run, 'cand', config.judges, 4);
  const r = score(run);
  assert.equal(r.verdict, 'INCOMPLETE');
  assert.deepEqual(failing(r.cand), ['baseline judgments complete']);
  assert.equal(r.baseVerdict, 'baseline (incomplete)');
});

test('a baseline with a failed first generation cannot anchor a PASS', () => {
  const run = tmpRun();
  // The baseline's first generation errored for t3, so it has nothing graded
  // there; its own judgments are complete for what it did produce.
  writeModel(run, 'base', { error: (t, rep) => t === 't3' && rep === 0 });
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3, { skip: (j, t) => t === 't3' });
  writeJudgments(run, 'cand', config.judges, 4);
  const r = score(run);
  assert.equal(r.base.judgmentsPresent, r.base.judgmentsExpected);
  assert.deepEqual(failing(r.cand), ['baseline graded on every transcript the candidate was']);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a judgment of an earlier summary is not counted after the model is regenerated', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { content: (t) => `regenerated summary of ${t}` });
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 5);   // hashes of the old text
  const r = score(run);
  assert.equal(r.cand.judgmentsPresent, 6);        // only the off-topic ones still match
  assert.equal(r.cand.quality, null);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a judgment with no hash of what it graded is missing evidence', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 5, { withSha: false });
  const r = score(run);
  assert.equal(r.cand.judgmentsPresent, 6);   // the off-topic ones carry a hash
  assert.equal(r.cand.quality, null);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a generation that errored needs no judgment but fails the completion gate', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { error: (t, rep) => t === 't3' && rep === 0 });
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4, { skip: (j, t) => t === 't3' });
  const r = score(run);
  assert.equal(r.cand.judgmentsExpected, 10);
  assert.equal(r.cand.judgmentsPresent, 10);
  assert.equal(r.verdict, 'FAIL (4)');   // completion, title, sections, refs section
  assert.ok(failing(r.cand).includes('completes (non-empty, not truncated)'));
});

test('quality more than the allowed margin below the baseline fails', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 4);
  writeJudgments(run, 'cand', config.judges, 3);
  const r = score(run);
  assert.equal(r.verdict, 'FAIL (3)');
  assert.deepEqual(failing(r.cand), ['faithfulness vs baseline', 'scripture accuracy vs baseline', 'quality vs baseline (pts)']);
});

test('a single faithfulness score under the floor fails even when the mean is fine', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 5);
  const f = path.join(run, 'judge', slug('vendor-a/judge'), slug('cand'), 't1.json');
  const j = JSON.parse(fs.readFileSync(f, 'utf8'));
  j.scores.faithfulness = 2;
  fs.writeFileSync(f, JSON.stringify(j));
  const r = score(run);
  assert.deepEqual(failing(r.cand), ['worst single faithfulness score']);
  assert.equal(r.verdict, 'FAIL (1)');
});

test('an off-topic reply one judge says answered the question fails the gate', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4, { offTopic: (j, t) => !(j === 'vendor-b/judge' && t === 't2') });
  const r = score(run);
  assert.deepEqual(failing(r.cand), ['off-topic redirect']);
  assert.equal(r.verdict, 'FAIL (1)');
  assert.equal(r.cand.failures.offTopic.length, 1);
});

test('an off-topic reply with no judge verdict is missing evidence, not a pass', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4, { skipOffTopic: () => true });
  const r = score(run);
  assert.equal(r.cand.judgmentsPresent, 6);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('an off-topic reply the code check rejected fails without needing a judge', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { offTopicCodeOk: (t) => t !== 't1' });
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4, { skipOffTopic: (j, t) => t === 't1' });
  const r = score(run);
  assert.equal(r.cand.judgmentsExpected, 10);
  assert.equal(r.cand.judgmentsPresent, 10);
  assert.deepEqual(failing(r.cand), ['off-topic redirect']);
});

test('latency p95 and cost gates sit exactly on their thresholds', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { latencyMs: 45000, costUsd: 0.002 });
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  assert.equal(score(run).verdict, 'PASS');

  const slow = tmpRun();
  writeModel(slow, 'base');
  writeModel(slow, 'cand', { latencyMs: 45001, costUsd: 0.0021 });
  writeJudgments(slow, 'base', config.judges, 3);
  writeJudgments(slow, 'cand', config.judges, 4);
  const r = score(slow);
  assert.deepEqual(failing(r.cand), ['latency p95', 'cost vs baseline']);
});

test('a measured failure outranks missing evidence', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { latencyMs: 60000 });
  writeJudgments(run, 'base', config.judges, 3);
  const r = score(run);
  assert.equal(r.verdict, 'FAIL (1)');
  assert.equal(r.cand.overBudget, 6);
});

test('a run interrupted before every generation was written is INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  assert.equal(score(run).verdict, 'PASS');
  // The second generation for t2 never landed. Nothing about the files that
  // do exist is wrong, which is exactly why the sample must be checked.
  fs.rmSync(path.join(run, 'gen', slug('cand'), 't2.r1.json'));
  const r = score(run);
  assert.equal(r.cand.generationsPresent, 5);
  assert.equal(r.cand.generationsExpected, 6);
  assert.deepEqual(failing(r.cand), ['all planned generations present']);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a missing first generation is missing evidence, not a smaller sample', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  fs.rmSync(path.join(run, 'gen', slug('cand'), 't3.r0.json'));
  const r = score(run);
  assert.equal(r.verdict, 'INCOMPLETE');
  assert.ok(failing(r.cand).includes('all planned generations present'));
});

test('a missing chat check is INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  fs.rmSync(path.join(run, 'chat', slug('cand'), 't1.json'));
  const r = score(run);
  assert.deepEqual(failing(r.cand), ['all planned chat checks present']);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a baseline missing a generation makes every candidate INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  fs.rmSync(path.join(run, 'gen', slug('base'), 't1.r1.json'));
  const r = score(run);
  assert.deepEqual(failing(r.cand), ['baseline generations and chat checks complete']);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a planned model with no output at all is INCOMPLETE and keeps its label', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeJudgments(run, 'base', config.judges, 3);
  const r = score(run);
  assert.equal(r.cand.model, 'cand');
  assert.equal(r.cand.generationsPresent, 0);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('files outside the plan are not counted', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  // A slow leftover from an earlier, larger manifest.
  write(path.join(run, 'gen', slug('cand'), 'old.r0.json'), {
    model: 'cand', transcript: 'old', rep: 0, tier: 'premium',
    result: { content: 'x', finishReason: 'stop', latencyMs: 99000, usage: { costUsd: 1 } }, check: goodCheck,
  });
  const r = score(run);
  assert.equal(r.cand.runs, 6);
  assert.equal(r.verdict, 'PASS');
});

test('a run with no recorded plan cannot pass', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  const r = score(run, config.judges, null);
  assert.equal(r.verdict, 'INCOMPLETE');
  assert.ok(failing(r.cand).includes('run plan recorded (plan.json)'));
});

test('one judge can fail a model but can only pass it provisionally', () => {
  const run = tmpRun();
  const one = ['vendor-a/judge'];
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', one, 3);
  writeJudgments(run, 'cand', one, 4);
  const r = score(run, one);
  assert.equal(r.verdict, 'PROVISIONAL (one judge vendor)');
  assert.deepEqual(failing(r.cand), ['judges from at least 2 vendors']);

  const worse = tmpRun();
  writeModel(worse, 'base');
  writeModel(worse, 'cand');
  writeJudgments(worse, 'base', one, 4);
  writeJudgments(worse, 'cand', one, 3);
  assert.equal(score(worse, one).verdict, 'FAIL (3)');
});

test('two judges from the same vendor are still one vendor', () => {
  const run = tmpRun();
  const same = ['vendor-a/judge', 'vendor-a/other-judge'];
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', same, 3);
  writeJudgments(run, 'cand', same, 4);
  assert.equal(score(run, same).verdict, 'PROVISIONAL (one judge vendor)');
});

test('missing evidence outranks a provisional reading', () => {
  const run = tmpRun();
  const one = ['vendor-a/judge'];
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', one, 3);
  writeJudgments(run, 'cand', one, 4, { skip: (j, t) => t === 't2' });
  assert.equal(score(run, one).verdict, 'INCOMPLETE');
});

test('a candidate with no baseline in the run is INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'cand');
  writeJudgments(run, 'cand', config.judges, 5);
  const cand = aggregate(run, slug('cand'), config, config.judges, PLAN);
  cand.gates = applyGates(cand, undefined, config);
  assert.equal(verdict(cand, false), 'INCOMPLETE');
  assert.deepEqual(failing(cand), ['baseline present in this run']);
});

// A file cut off mid-write, as a killed process or a full disk leaves it.
const truncate = (f) => fs.writeFileSync(f, fs.readFileSync(f, 'utf8').slice(0, 25));

function passingRun() {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4);
  assert.equal(score(run).verdict, 'PASS');
  return run;
}

test('a truncated generation file is missing evidence, not a crash', () => {
  const run = passingRun();
  truncate(path.join(run, 'gen', slug('cand'), 't2.r1.json'));
  const r = score(run);
  assert.equal(r.cand.generationsPresent, 5);
  assert.deepEqual(failing(r.cand), ['all planned generations present']);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a truncated chat file is missing evidence, not a crash', () => {
  const run = passingRun();
  truncate(path.join(run, 'chat', slug('cand'), 't1.json'));
  const r = score(run);
  assert.ok(failing(r.cand).includes('all planned chat checks present'));
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a truncated judgment file is missing evidence, not a crash', () => {
  const run = passingRun();
  truncate(path.join(run, 'judge', slug('vendor-a/judge'), slug('cand'), 't3.json'));
  truncate(path.join(run, 'judge', slug('vendor-b/judge'), slug('cand'), 'offtopic.t1.json'));
  const r = score(run);
  assert.equal(r.cand.judgmentsPresent, 10);
  assert.deepEqual(failing(r.cand), ['judgments complete']);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a truncated baseline file makes the candidate INCOMPLETE', () => {
  const run = passingRun();
  truncate(path.join(run, 'gen', slug('base'), 't1.r0.json'));
  assert.equal(score(run).verdict, 'INCOMPLETE');
});

test('an unreadable plan or judge list is treated as not recorded', () => {
  const run = passingRun();
  fs.writeFileSync(path.join(run, 'plan.json'), '{"transcripts":["t1"');
  fs.writeFileSync(path.join(run, 'judges.json'), '["vendor-a/ju');
  assert.equal(loadPlan(run), null);
  assert.deepEqual(resolveJudges(run, config, null), config.judges);
  const r = score(run, config.judges, loadPlan(run));
  assert.ok(failing(r.cand).includes('run plan recorded (plan.json)'));
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('a temporary file left in a model folder is not read as a result', () => {
  const run = passingRun();
  // Whole, valid JSON: a write that finished but was never renamed into place.
  fs.copyFileSync(path.join(run, 'gen', slug('cand'), 't1.r0.json'), path.join(run, 'gen', slug('cand'), 't1.r0.json.123.tmp'));
  assert.equal(score(run).verdict, 'PASS');
  assert.equal(aggregate(run, slug('cand'), config, config.judges, null).generationsPresent, 6);
});

test('the first invocation records the plan it was given', () => {
  assert.deepEqual(mergePlan(null, { ...PLAN, models: ['base', 'base'] }), { ...PLAN, models: ['base'] });
});

test('a later invocation may add models and nothing else', () => {
  const merged = mergePlan(PLAN, { ...PLAN, models: ['cand', 'third'] });
  assert.deepEqual(merged, { ...PLAN, models: ['base', 'cand', 'third'] });
});

test('a resumed run cannot shrink, or otherwise change, the planned sample', () => {
  assert.throws(() => mergePlan(PLAN, { ...PLAN, repeats: 1 }), /planned with 2 generations per transcript, not 1/);
  assert.throws(() => mergePlan(PLAN, { ...PLAN, repeats: 3 }), /planned with 2 generations/);
  assert.throws(() => mergePlan(PLAN, { ...PLAN, chatTranscripts: ['t1'] }), /different set of transcripts or chat checks/);
  assert.throws(() => mergePlan(PLAN, { ...PLAN, transcripts: ['t1', 't2'] }), /different set of transcripts or chat checks/);
});

test('a run missing its second generations stays INCOMPLETE under the plan it was started with', () => {
  const run = passingRun();
  for (const t of TRANSCRIPTS) fs.rmSync(path.join(run, 'gen', slug('cand'), `${t}.r1.json`));
  // What the old code would have recorded after a resume with --repeats 1.
  assert.equal(score(run, config.judges, { ...PLAN, repeats: 1 }).verdict, 'PASS');
  assert.throws(() => mergePlan(PLAN, { ...PLAN, repeats: 1 }));
  assert.equal(score(run).verdict, 'INCOMPLETE');
});

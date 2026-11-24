'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { slug, sha, pct, resolveJudges, aggregate, applyGates, verdict } = require('../lib/score');

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
  const { latencyMs = 10000, costUsd = 0.001, content = (t) => `summary of ${t} by ${label}`, error = null } = opts;
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
    write(path.join(runDir, 'chat', slug(label), `${t}.json`), { questions: { ok: true }, offTopic: { ok: true } });
  }
}

function writeJudgments(runDir, label, judges, value, opts = {}) {
  const { skip = () => false, summary = (t) => `summary of ${t} by ${label}`, withSha = true } = opts;
  for (const judge of judges) {
    for (const t of TRANSCRIPTS) {
      if (skip(judge, t)) continue;
      write(path.join(runDir, 'judge', slug(judge), slug(label), `${t}.json`), {
        judge, model: label, transcript: t, scores: scoresOf(value), ...(withSha ? { summarySha: sha(summary(t)) } : {}),
      });
    }
  }
}

function tmpRun() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'model-eval-'));
}

// Baseline plus one candidate, graded; returns the candidate's verdict inputs.
function score(runDir, judges = config.judges) {
  const base = aggregate(runDir, slug('base'), config, judges);
  const cand = aggregate(runDir, slug('cand'), config, judges);
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
  assert.equal(r.cand.judgmentsExpected, 6);
  assert.equal(r.cand.judgmentsPresent, 6);
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
  const used = ['vendor-c/other'];
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
  assert.equal(r.cand.judgmentsPresent, 5);
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

test('a judgment of an earlier summary is not counted after the model is regenerated', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { content: (t) => `regenerated summary of ${t}` });
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 5);   // hashes of the old text
  const r = score(run);
  assert.equal(r.cand.judgmentsPresent, 0);
  assert.equal(r.cand.quality, null);
  assert.equal(r.verdict, 'INCOMPLETE');
});

test('judgments written before summarySha existed are still accepted', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand');
  writeJudgments(run, 'base', config.judges, 3, { withSha: false });
  writeJudgments(run, 'cand', config.judges, 4, { withSha: false });
  assert.equal(score(run).verdict, 'PASS');
});

test('a generation that errored needs no judgment but fails the completion gate', () => {
  const run = tmpRun();
  writeModel(run, 'base');
  writeModel(run, 'cand', { error: (t, rep) => t === 't3' && rep === 0 });
  writeJudgments(run, 'base', config.judges, 3);
  writeJudgments(run, 'cand', config.judges, 4, { skip: (j, t) => t === 't3' });
  const r = score(run);
  assert.equal(r.cand.judgmentsExpected, 4);
  assert.equal(r.cand.judgmentsPresent, 4);
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

test('a candidate with no baseline in the run is INCOMPLETE', () => {
  const run = tmpRun();
  writeModel(run, 'cand');
  writeJudgments(run, 'cand', config.judges, 5);
  const cand = aggregate(run, slug('cand'), config, config.judges);
  cand.gates = applyGates(cand, undefined, config);
  assert.equal(verdict(cand, false), 'INCOMPLETE');
  assert.deepEqual(failing(cand), ['baseline present in this run']);
});

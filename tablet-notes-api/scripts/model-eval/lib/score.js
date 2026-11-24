'use strict';

// Aggregation, gates and verdicts. Everything that decides PASS or FAIL lives
// here, free of network and CLI concerns, so it can be tested with fixture runs.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const { KEYS } = require('./judge');
const { readJson, readJsonOrNull } = require('./files');

const slug = (s) => s.replace(/[^a-zA-Z0-9.-]+/g, '_');
const sha = (s) => crypto.createHash('sha1').update(s).digest('hex');
const mean = (xs) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
const rate = (xs, f) => xs.length ? xs.filter(f).length / xs.length : null;
function pct(xs, p) {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)];
}

// A generation the judges can grade: it returned text. Errors and empty
// output are already failed by the completion gate.
const gradable = (gen) => !gen.result.error && !!(gen.result.content || '').trim();

// Which judges a run was graded by. `judge` records the list it used, so a
// `--judges` override at judge time cannot leave `report` looking in the
// config's folders and finding nothing.
function resolveJudges(runDir, config, override) {
  if (override && override.length) return override;
  const file = path.join(runDir, 'judges.json');
  const recorded = readJsonOrNull(file);
  return Array.isArray(recorded) && recorded.length ? recorded : config.judges;
}

// A stored judgment counts only if it can show it graded the text that is on
// disk now. One with no hash cannot show that, so it is missing evidence:
// `judge` redoes it and `report` stays INCOMPLETE until it has.
function loadJudgment(file, summary) {
  const j = readJsonOrNull(file);   // absent or unreadable: no judgment
  if (!j || j.summarySha !== sha(summary)) return null;
  return j;
}

// What `run` set out to produce, written to runs/<run>/plan.json. The report
// measures against this, so an interrupted run or a deleted file shows up as
// missing evidence instead of quietly shrinking the sample.
function loadPlan(runDir) {
  const file = path.join(runDir, 'plan.json');
  return readJsonOrNull(file);
}

// A result file that is absent or cannot be parsed is not a result.
// The plan a `run` invocation records. A run's sample is fixed by its first
// invocation: a later one may add models, but asking for a different number
// of generations or chat checks is refused, because rewriting the plan to a
// smaller one would turn an unfinished run into a finished smaller one.
function mergePlan(before, now) {
  if (!before) return { ...now, models: [...new Set(now.models)] };
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  if (before.repeats !== now.repeats) {
    throw new Error(`this run was planned with ${before.repeats} generations per transcript, not ${now.repeats}; use --repeats ${before.repeats} or start a new run`);
  }
  if (!same(before.transcripts, now.transcripts) || !same(before.chatTranscripts, now.chatTranscripts)) {
    throw new Error('this run was planned with a different set of transcripts or chat checks; start a new run');
  }
  return { ...before, models: [...new Set([...before.models, ...now.models])] };
}

function readPlanned(dir, names) {
  return names.map(n => readJsonOrNull(path.join(dir, n))).filter(Boolean);
}

function aggregate(runDir, modelSlug, config, judges, plan) {
  const genDir = path.join(runDir, 'gen', modelSlug);
  const chatDir = path.join(runDir, 'chat', modelSlug);
  const list = (dir) => fs.existsSync(dir) ? fs.readdirSync(dir).filter(n => n.endsWith('.json')) : [];
  // With a plan, only planned files count and every one of them is expected.
  // Without one there is no way to know what is missing; applyGates says so.
  const genNames = plan ? plan.transcripts.flatMap(t => Array.from({ length: plan.repeats }, (_, rep) => `${t}.r${rep}.json`)) : list(genDir);
  const chatNames = plan ? plan.chatTranscripts.map(t => `${t}.json`) : list(chatDir);
  const gens = readPlanned(genDir, genNames);
  const chats = readPlanned(chatDir, chatNames);
  const ok = gens.filter(g => g.check);
  const label = plan && (plan.models.find(l => slug(l) === modelSlug));
  const refTotal = ok.reduce((n, g) => n + g.check.refCount, 0);
  const quoteTotal = ok.reduce((n, g) => n + g.check.quoteCount, 0);

  // Walk the judgments the run should have (first generation of each
  // transcript, every judge) rather than whatever files happen to exist.
  const judged = {};          // transcript -> judge -> scores
  const perJudge = {};
  let judgmentsExpected = 0, judgmentsPresent = 0;
  const gradedTranscripts = gens.filter(g => g.rep === 0 && gradable(g)).map(g => g.transcript);
  for (const gen of gens.filter(g => g.rep === 0 && gradable(g))) {
    for (const judge of judges) {
      judgmentsExpected++;
      const j = loadJudgment(path.join(runDir, 'judge', slug(judge), modelSlug, `${gen.transcript}.json`), gen.result.content);
      if (!j) continue;
      judgmentsPresent++;
      (judged[gen.transcript] = judged[gen.transcript] || {})[judge] = j.scores;
      (perJudge[judge] = perJudge[judge] || []).push(j.scores);
    }
  }
  // The off-topic reply passes only if the code check passed and every judge
  // says it redirected without answering. A reply with no text needs no judge.
  const offTopicFailures = [];
  const offTopicOk = (c) => {
    if (!c.offTopic.ok) { offTopicFailures.push(`${String(c.transcript).slice(0, 8)}: code check`); return false; }
    let ok = true;
    for (const judge of judges) {
      judgmentsExpected++;
      const j = loadJudgment(path.join(runDir, 'judge', slug(judge), modelSlug, `offtopic.${c.transcript}.json`), c.offTopic.result.content);
      if (!j) continue;
      judgmentsPresent++;
      if (!j.verdict.redirectOnly) { ok = false; offTopicFailures.push(`${String(c.transcript).slice(0, 8)}: ${judge.split('/').pop()}: ${j.verdict.note}`); }
    }
    return ok;
  };
  const offTopicResults = chats.map(offTopicOk);

  // Average the judges per transcript, then average transcripts.
  const perTranscript = Object.values(judged).map(byJudge => {
    const row = {};
    for (const k of KEYS) row[k] = mean(Object.values(byJudge).map(s => s[k]));
    return row;
  });
  const scores = {};
  for (const k of KEYS) scores[k] = mean(perTranscript.map(r => r[k]));
  const weighted = (get) => 100 * KEYS.reduce((n, k) => n + config.weights[k] * (get(k) - 1) / 4, 0);
  const quality = perTranscript.length ? weighted(k => scores[k]) : null;
  const allScores = Object.values(judged).flatMap(b => Object.values(b));

  return {
    model: gens[0] ? gens[0].model : (label || modelSlug),
    runs: gens.length,
    planned: !!plan,
    generationsExpected: genNames.length,
    generationsPresent: gens.length,
    chatsExpected: chatNames.length,
    chatsPresent: chats.length,
    judgeVendors: new Set(judges.map(j => j.split('/')[0])).size,
    errors: gens.filter(g => g.result.error).map(g => g.result.error),
    completionRate: rate(gens, g => g.check && g.check.completed),
    truncatedRate: rate(gens, g => g.check && g.check.truncated),
    titleRate: rate(gens, g => g.check && g.check.titleOk),
    sectionsRate: rate(gens, g => g.check && g.check.sectionsOk),
    scriptureSectionWithRefRate: rate(gens, g => g.check && g.check.scriptureSectionHasRef),
    premiumLeakRate: rate(ok.filter(g => g.tier === 'basic'), g => g.check.premiumLeak.length > 0),
    bookUngroundedRefRate: refTotal ? ok.reduce((n, g) => n + g.check.refsBookUngrounded.length, 0) / refTotal : 0,
    chapterGroundedRefRate: refTotal ? ok.reduce((n, g) => n + g.check.refsChapterGrounded, 0) / refTotal : null,
    refsPerSummary: ok.length ? refTotal / ok.length : null,
    quotesPerSummary: ok.length ? quoteTotal / ok.length : null,
    quoteVerbatimRate: quoteTotal ? ok.reduce((n, g) => n + g.check.quotesVerbatim, 0) / quoteTotal : null,
    quoteFabricatedRate: quoteTotal ? ok.reduce((n, g) => n + g.check.quotesFabricated.length, 0) / quoteTotal : null,
    latencyP50Ms: pct(gens.map(g => g.result.latencyMs), 0.5),
    latencyP95Ms: pct(gens.map(g => g.result.latencyMs), 0.95),
    overBudget: gens.filter(g => g.result.latencyMs > 55000).length,
    costUsd: mean(ok.map(g => g.result.usage.costUsd).filter(c => c != null)),
    outputTokens: mean(ok.map(g => g.result.usage.completionTokens).filter(c => c != null)),
    questionsJsonRate: rate(chats, c => c.questions.ok),
    offTopicRedirectRate: rate(offTopicResults, ok => ok),
    judgmentsExpected,
    judgmentsPresent,
    gradedTranscripts,
    judgedCount: perTranscript.length,
    scores,
    quality,
    worstFaithfulness: allScores.length ? Math.min(...allScores.map(s => s.faithfulness)) : null,
    unsupportedClaimsPerSummary: allScores.length ? mean(allScores.map(s => s.unsupported_claims.length)) : null,
    mainScriptureWrong: allScores.filter(s => s.main_scripture_correct === false).length,
    perJudgeFaithfulness: Object.fromEntries(Object.entries(perJudge).map(([j, ss]) => [j, mean(ss.map(s => s.faithfulness))])),
    perJudgeQuality: Object.fromEntries(Object.entries(perJudge).map(([j, ss]) => [j, weighted(k => mean(ss.map(s => s[k])))])),
    failures: {
      missingSections: ok.filter(g => !g.check.sectionsOk).map(g => `${g.transcript.slice(0, 8)}.r${g.rep}: ${g.check.missingSections.join(', ')}`),
      ungroundedRefs: ok.flatMap(g => g.check.refsBookUngrounded.map(r => `${g.transcript.slice(0, 8)}.r${g.rep}: ${r}`)),
      offTopic: offTopicFailures,
    },
  };
}

const judgmentsComplete = (m) => m.judgmentsExpected > 0 && m.judgmentsPresent === m.judgmentsExpected;
const outputsComplete = (m) => m.planned && m.generationsExpected > 0 && m.generationsPresent === m.generationsExpected && m.chatsPresent === m.chatsExpected;

// Gate rows for one model. A row with `evidence: true` is not a quality
// failure: it says the evidence for a verdict is missing, and turns the
// verdict into INCOMPLETE. A model is never passed on mechanical gates alone,
// on part of the planned sample, or on judges from a single vendor.
function applyGates(m, base, config) {
  const g = config.gates;
  const isBase = m === base;
  const pc = (v) => `${Math.round(v * 100)}%`;
  const n2 = (v) => v.toFixed(2);
  const sg = (v) => (v >= 0 ? '+' : '') + v.toFixed(2);
  const rows = [
    ['completes (non-empty, not truncated)', m.completionRate, v => v >= g.completionRate, pc],
    ['TITLE: line parseable', m.titleRate, v => v >= g.titleRate, pc],
    ['all required sections', m.sectionsRate, v => v >= g.sectionsRate, pc],
    ['Scripture References has a reference', m.scriptureSectionWithRefRate, v => v >= g.scriptureSectionWithRefRate, pc],
    ['latency p95', m.latencyP95Ms, v => v <= g.latencyP95MsMax, v => `${(v / 1000).toFixed(1)} s`],
    ['questions JSON contract', m.questionsJsonRate, v => v >= g.questionsJsonRate, pc],
    ['off-topic redirect', m.offTopicRedirectRate, v => v >= g.offTopicRedirectRate, pc],
  // A gate with nothing to measure is missing evidence, not a measured failure.
  ].map(([name, value, test, fmt]) => value == null
    ? { name, value, shown: 'n/a', pass: false, evidence: true }
    : { name, value, shown: fmt(value), pass: test(value) });
  const add = (name, value, test, fmt) => rows.push({ name, value, shown: value == null ? 'n/a' : fmt(value), pass: value != null && test(value) });
  const evidence = (name, pass, shown) => rows.push({ name, value: null, shown, pass, evidence: true });

  if (!m.planned) evidence('run plan recorded (plan.json)', false, 'missing');
  evidence('all planned generations present', m.planned && m.generationsExpected > 0 && m.generationsPresent === m.generationsExpected, `${m.generationsPresent}/${m.generationsExpected}`);
  evidence('all planned chat checks present', m.planned && m.chatsPresent === m.chatsExpected, `${m.chatsPresent}/${m.chatsExpected}`);
  evidence('judgments complete', judgmentsComplete(m), `${m.judgmentsPresent}/${m.judgmentsExpected}`);
  // The standard is two judges from different vendors, so that a judge
  // favouring its own vendor's model is outvoted. Fewer is a cheaper,
  // provisional reading: it can fail a model but cannot pass one.
  const minVendors = g.minJudgeVendors ?? 2;
  if (m.judgeVendors < minVendors) rows.push({ name: `judges from at least ${minVendors} vendors`, value: null, shown: String(m.judgeVendors), pass: false, evidence: true, provisional: true });
  if (m.judgedCount) add('worst single faithfulness score', m.worstFaithfulness, v => v >= g.worstFaithfulnessMin, n2);

  if (!isBase) {
    if (!base) {
      evidence('baseline present in this run', false, 'missing');
    } else {
      if (!outputsComplete(base)) evidence('baseline generations and chat checks complete', false, `${base.generationsPresent}/${base.generationsExpected}, ${base.chatsPresent}/${base.chatsExpected}`);
      if (!judgmentsComplete(base)) evidence('baseline judgments complete', false, `${base.judgmentsPresent}/${base.judgmentsExpected}`);
      // The comparison is only fair over the same sermons. If the baseline's
      // first generation failed for a transcript the candidate was graded on,
      // the two means cover different populations.
      const have = new Set(base.gradedTranscripts);
      const unmatched = m.gradedTranscripts.filter(t => !have.has(t));
      if (unmatched.length) evidence('baseline graded on every transcript the candidate was', false, `${unmatched.length} without a baseline summary`);
      if (m.judgedCount && base.judgedCount) {
        add('faithfulness vs baseline', m.scores.faithfulness - base.scores.faithfulness, v => v >= g.faithfulnessVsBaselineMin, sg);
        add('scripture accuracy vs baseline', m.scores.scripture - base.scores.scripture, v => v >= g.scriptureVsBaselineMin, sg);
        add('quality vs baseline (pts)', m.quality - base.quality, v => v >= g.qualityVsBaselineMin, sg);
      }
      // A baseline that costs nothing has no ratio: a candidate that is also
      // free matches it, and one that costs anything is infinitely dearer.
      // Only a cost that was never reported is missing evidence.
      if (m.costUsd != null && base.costUsd != null) {
        const ratio = base.costUsd === 0 ? (m.costUsd === 0 ? 1 : Infinity) : m.costUsd / base.costUsd;
        add('cost vs baseline', ratio, v => v <= g.costVsBaselineMax, v => Number.isFinite(v) ? `${v.toFixed(2)}x` : 'baseline is free');
      } else evidence('cost vs baseline', false, 'n/a');
    }
  }
  return rows;
}

// FAIL outranks INCOMPLETE: a model that failed a measured gate has failed
// whether or not the rest of the evidence is in.
function verdict(m, isBase) {
  const failed = m.gates.filter(x => !x.pass && !x.evidence).length;
  const incomplete = m.gates.some(x => !x.pass && x.evidence && !x.provisional);
  const provisional = m.gates.some(x => !x.pass && x.provisional);
  if (isBase) {
    if (failed) return `baseline (${failed} gate${failed > 1 ? 's' : ''} failed)`;
    return incomplete ? 'baseline (incomplete)' : 'baseline';
  }
  if (failed) return `FAIL (${failed})`;
  if (incomplete) return 'INCOMPLETE';
  // Everything that was measured passed, but not under the full standard.
  return provisional ? 'PROVISIONAL (one judge vendor)' : 'PASS';
}

module.exports = { slug, sha, readJson, readJsonOrNull, mean, rate, pct, gradable, resolveJudges, loadJudgment, loadPlan, mergePlan, aggregate, applyGates, verdict, judgmentsComplete };

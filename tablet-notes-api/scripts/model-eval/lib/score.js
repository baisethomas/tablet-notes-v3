'use strict';

// Aggregation, gates and verdicts. Everything that decides PASS or FAIL lives
// here, free of network and CLI concerns, so it can be tested with fixture runs.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const { KEYS } = require('./judge');

const slug = (s) => s.replace(/[^a-zA-Z0-9.-]+/g, '_');
const sha = (s) => crypto.createHash('sha1').update(s).digest('hex');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
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
  if (fs.existsSync(file)) return readJson(file);
  return config.judges;
}

// A stored judgment counts only if it graded the summary that is on disk now.
// Judgments written before `summarySha` existed carry no hash and are accepted.
function loadJudgment(file, summary) {
  if (!fs.existsSync(file)) return null;
  const j = readJson(file);
  if (j.summarySha != null && j.summarySha !== sha(summary)) return null;
  return j;
}

function aggregate(runDir, modelSlug, config, judges) {
  const gens = fs.readdirSync(path.join(runDir, 'gen', modelSlug)).map(f => readJson(path.join(runDir, 'gen', modelSlug, f)));
  const ok = gens.filter(g => g.check);
  const chatDir = path.join(runDir, 'chat', modelSlug);
  const chats = fs.existsSync(chatDir) ? fs.readdirSync(chatDir).map(f => readJson(path.join(chatDir, f))) : [];
  const refTotal = ok.reduce((n, g) => n + g.check.refCount, 0);
  const quoteTotal = ok.reduce((n, g) => n + g.check.quoteCount, 0);

  // Walk the judgments the run should have (first generation of each
  // transcript, every judge) rather than whatever files happen to exist.
  const judged = {};          // transcript -> judge -> scores
  const perJudge = {};
  let judgmentsExpected = 0, judgmentsPresent = 0;
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
    model: gens[0] ? gens[0].model : modelSlug,
    runs: gens.length,
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
    offTopicRedirectRate: rate(chats, c => c.offTopic.ok),
    judgmentsExpected,
    judgmentsPresent,
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
    },
  };
}

const judgmentsComplete = (m) => m.judgmentsExpected > 0 && m.judgmentsPresent === m.judgmentsExpected;

// Gate rows for one model. A row with `evidence: true` is not a quality
// failure: it says the evidence for a verdict is missing, and turns the
// verdict into INCOMPLETE. A model is never passed on mechanical gates alone.
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
  ].map(([name, value, test, fmt]) => ({ name, value, shown: value == null ? 'n/a' : fmt(value), pass: value != null && test(value) }));
  const add = (name, value, test, fmt) => rows.push({ name, value, shown: value == null ? 'n/a' : fmt(value), pass: value != null && test(value) });
  const evidence = (name, pass, shown) => rows.push({ name, value: null, shown, pass, evidence: true });

  evidence('judgments complete', judgmentsComplete(m), `${m.judgmentsPresent}/${m.judgmentsExpected}`);
  if (m.judgedCount) add('worst single faithfulness score', m.worstFaithfulness, v => v >= g.worstFaithfulnessMin, n2);

  if (!isBase) {
    if (!base) {
      evidence('baseline present in this run', false, 'missing');
    } else {
      if (!judgmentsComplete(base)) evidence('baseline judgments complete', false, `${base.judgmentsPresent}/${base.judgmentsExpected}`);
      if (m.judgedCount && base.judgedCount) {
        add('faithfulness vs baseline', m.scores.faithfulness - base.scores.faithfulness, v => v >= g.faithfulnessVsBaselineMin, sg);
        add('scripture accuracy vs baseline', m.scores.scripture - base.scores.scripture, v => v >= g.scriptureVsBaselineMin, sg);
        add('quality vs baseline (pts)', m.quality - base.quality, v => v >= g.qualityVsBaselineMin, sg);
      }
      if (m.costUsd != null && base.costUsd) add('cost vs baseline', m.costUsd / base.costUsd, v => v <= g.costVsBaselineMax, v => `${v.toFixed(2)}x`);
      else evidence('cost vs baseline', false, 'n/a');
    }
  }
  return rows;
}

// FAIL outranks INCOMPLETE: a model that failed a measured gate has failed
// whether or not the rest of the evidence is in.
function verdict(m, isBase) {
  const failed = m.gates.filter(x => !x.pass && !x.evidence).length;
  const incomplete = m.gates.some(x => !x.pass && x.evidence);
  if (isBase) {
    if (failed) return `baseline (${failed} gate${failed > 1 ? 's' : ''} failed)`;
    return incomplete ? 'baseline (incomplete)' : 'baseline';
  }
  if (failed) return `FAIL (${failed})`;
  return incomplete ? 'INCOMPLETE' : 'PASS';
}

module.exports = { slug, sha, readJson, mean, rate, pct, gradable, resolveJudges, loadJudgment, aggregate, applyGates, verdict, judgmentsComplete };

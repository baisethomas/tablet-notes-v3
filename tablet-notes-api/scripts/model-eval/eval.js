#!/usr/bin/env node
'use strict';

// Replacement-model evaluation for the TabletNotes AI endpoints.
// See README.md for the standards this implements.
//
//   node eval.js pull   --source supabase --users <uuid,uuid> [--n 12]
//   node eval.js pull   --source assemblyai [--n 12]
//   node eval.js run    --run <name> [--models "a;b"] [--repeats 2]
//   node eval.js judge  --run <name>
//   node eval.js report --run <name>

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const { assemblyKey } = require('./lib/keys');
const { chat, pool } = require('./lib/openrouter');
const { loadSummarize, loadChat } = require('./lib/prompt');
const checks = require('./lib/checks');
const { judgeSummary, KEYS } = require('./lib/judge');

const ROOT = __dirname;
const DATA = path.join(ROOT, 'data');
const config = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));

const MIN_CHARS = 8000;     // below this it is a test clip, not a sermon
const MAX_CHARS = 150000;   // LIMITS.SUMMARY_TEXT_LENGTH
const OFF_TOPIC = "Who should I vote for in the next election, and what's a good stock to buy this week?";

// ---------- small helpers ----------

function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) out[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    else out._.push(argv[i]);
  }
  return out;
}
const slug = (s) => s.replace(/[^a-zA-Z0-9.-]+/g, '_');
const sha = (s) => crypto.createHash('sha1').update(s).digest('hex');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const writeJson = (f, d) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(d, null, 2)); };
const mean = (xs) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
const rate = (xs, f) => xs.length ? xs.filter(f).length / xs.length : null;
function pct(xs, p) {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)];
}

// ---------- pull ----------

async function pullSupabase(a) {
  if (!a.users) throw new Error('--users <uuid,uuid> is required for --source supabase (whose transcripts may leave the building is a decision, not a default)');
  const ref = process.env.SUPABASE_PROJECT_REF || 'ubghnmenxbhhlpxvypea';
  const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', ref, '-o', 'json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
  const key = (keys.find(k => k.name === 'service_role') || {}).api_key;
  if (!key) throw new Error('could not resolve the Supabase service_role key via the supabase CLI');
  // Read-only: GET requests only. This script never writes to prod.
  const get = async (q) => {
    const res = await fetch(`https://${ref}.supabase.co/rest/v1/${q}`, { headers: { apikey: key, authorization: `Bearer ${key}` } });
    if (!res.ok) throw new Error(`supabase GET failed: ${res.status} ${(await res.text()).slice(0, 200)}`);
    return res.json();
  };
  const users = `in.(${a.users})`;
  const sermons = await get(`sermons?select=id,service_type,duration&user_id=${users}&deleted_at=is.null`);
  const byId = new Map(sermons.map(s => [s.id, s]));
  const transcripts = await get(`transcripts?select=id,sermon_id,text&user_id=${users}`);
  return transcripts.filter(t => byId.has(t.sermon_id)).map(t => ({
    id: t.id,
    source: 'supabase',
    serviceType: byId.get(t.sermon_id).service_type || 'Sermon',
    durationSec: byId.get(t.sermon_id).duration ?? null,
    text: t.text || '',
  }));
}

async function pullAssembly(a) {
  const key = assemblyKey();
  const want = Number(a.n || 12) * 3;
  const listed = [];
  let url = 'https://api.assemblyai.com/v2/transcript?limit=200&status=completed';
  for (let page = 0; page < 10 && url; page++) {
    const res = await fetch(url, { headers: { authorization: key } });
    if (!res.ok) throw new Error(`assemblyai list failed: ${res.status}`);
    const j = await res.json();
    listed.push(...j.transcripts);
    url = j.page_details && j.page_details.next_url;
  }
  listed.sort((x, y) => sha(x.id).localeCompare(sha(y.id)));
  const out = [];
  for (const item of listed) {
    if (out.length >= want) break;
    const res = await fetch(`https://api.assemblyai.com/v2/transcript/${item.id}`, { headers: { authorization: key } });
    if (!res.ok) continue;
    const t = await res.json();
    if (!t.text || t.text.length < MIN_CHARS) continue;
    // AssemblyAI does not know the service type; the app's default is "Sermon".
    out.push({ id: t.id, source: 'assemblyai', serviceType: 'Sermon', durationSec: t.audio_duration ?? null, text: t.text });
  }
  return out;
}

async function cmdPull(a) {
  const n = Number(a.n || 12);
  const all = a.source === 'assemblyai' ? await pullAssembly(a) : await pullSupabase(a);
  const seen = new Set();
  const usable = all.filter(t => {
    if (t.text.length < MIN_CHARS || t.text.length > MAX_CHARS) return false;
    const fp = sha(t.text.slice(0, 600).toLowerCase().replace(/\W+/g, ''));
    if (seen.has(fp)) return false;       // the same sermon recorded twice
    seen.add(fp);
    return true;
  });
  // Stratify by service type, deterministic order within a type.
  const groups = new Map();
  for (const t of usable.sort((x, y) => sha(x.id).localeCompare(sha(y.id)))) {
    if (!groups.has(t.serviceType)) groups.set(t.serviceType, []);
    groups.get(t.serviceType).push(t);
  }
  const picked = [];
  while (picked.length < n && [...groups.values()].some(g => g.length)) {
    for (const g of groups.values()) if (g.length && picked.length < n) picked.push(g.shift());
  }
  fs.rmSync(path.join(DATA, 'transcripts'), { recursive: true, force: true });
  const manifest = picked.map((t, i) => {
    writeJson(path.join(DATA, 'transcripts', `${t.id}.json`), t);
    // Alternate tiers so both output specs are exercised on the same models.
    return { id: t.id, source: t.source, serviceType: t.serviceType, chars: t.text.length, durationSec: t.durationSec, tier: i % 2 === 0 ? 'premium' : 'basic' };
  });
  writeJson(path.join(DATA, 'manifest.json'), manifest);
  console.log(`pulled ${all.length}, usable ${usable.length}, selected ${manifest.length}`);
  for (const m of manifest) console.log(`  ${m.id.slice(0, 8)}  ${m.serviceType.padEnd(16)} ${String(m.chars).padStart(6)} chars  ${m.tier}`);
}

// ---------- run ----------

function loadSet() {
  const manifest = readJson(path.join(DATA, 'manifest.json'));
  return manifest.map(m => ({ ...m, text: readJson(path.join(DATA, 'transcripts', `${m.id}.json`)).text }));
}
// A candidate is a model id, or { label, model, params } to test the same
// model under a different request configuration (e.g. reasoning disabled).
function models(a) {
  const all = [config.baseline, ...config.candidates].map(c =>
    typeof c === 'string' ? { label: c, model: c, params: {} } : { params: {}, ...c });
  if (!a.models) return all;
  const want = a.models.split(';').map(s => s.trim());   // labels may contain commas
  return all.filter(c => want.includes(c.label));
}

async function cmdRun(a) {
  const runDir = path.join(ROOT, 'runs', a.run);
  const set = loadSet();
  const summarize = loadSummarize();
  const chatSpec = loadChat();
  const repeats = Number(a.repeats || config.repeats);
  const indexes = new Map(set.map(t => [t.id, checks.transcriptIndex(t.text)]));
  if (summarize.prodModel !== config.baseline.split('/').pop()) {
    console.warn(`note: production runs ${summarize.prodModel}; config baseline is ${config.baseline}`);
  }

  const jobs = [];
  for (const c of models(a)) {
    const base = { label: c.label, model: c.model, extra: c.params };
    for (const t of set) {
      for (let rep = 0; rep < repeats; rep++) {
        jobs.push({ ...base, kind: 'summary', t, rep, file: path.join(runDir, 'gen', slug(c.label), `${t.id}.r${rep}.json`) });
      }
    }
    for (const t of set.slice(0, config.chatTranscripts)) {
      jobs.push({ ...base, kind: 'chat', t, file: path.join(runDir, 'chat', slug(c.label), `${t.id}.json`) });
    }
  }
  const todo = jobs.filter(j => !fs.existsSync(j.file));
  console.log(`${jobs.length} jobs, ${todo.length} to run`);

  let done = 0;
  await pool(todo, config.concurrency, async (j) => {
    if (j.kind === 'summary') {
      const result = await chat(j.model, summarize.messages(j.t), { ...summarize.params, ...j.extra });
      const check = result.error ? null : checks.checkSummary({
        content: result.content, finishReason: result.finishReason, tier: j.t.tier, transcript: j.t.text, index: indexes.get(j.t.id),
      });
      writeJson(j.file, { model: j.label, apiModel: j.model, params: j.extra, transcript: j.t.id, rep: j.rep, tier: j.t.tier, serviceType: j.t.serviceType, result, check });
    } else {
      const context = { title: 'Sunday message', serviceType: j.t.serviceType, transcript: j.t.text };
      const q = await chat(j.model, chatSpec.questions.messages(context), { ...chatSpec.questions.params, ...j.extra });
      const off = await chat(j.model, chatSpec.chat.messages(context, OFF_TOPIC), { ...chatSpec.chat.params, ...j.extra });
      writeJson(j.file, {
        model: j.label, apiModel: j.model, transcript: j.t.id,
        questions: { result: q, ok: !q.error && checks.checkQuestions(q.content) },
        offTopic: { result: off, ok: !off.error && checks.checkOffTopicRedirect(off.content) },
      });
    }
    if (++done % 10 === 0 || done === todo.length) console.log(`  ${done}/${todo.length}`);
  });
}

// ---------- judge ----------

async function cmdJudge(a) {
  const runDir = path.join(ROOT, 'runs', a.run);
  const set = new Map(loadSet().map(t => [t.id, t]));
  const jobs = [];
  for (const model of fs.readdirSync(path.join(runDir, 'gen'))) {
    for (const f of fs.readdirSync(path.join(runDir, 'gen', model)).filter(f => f.endsWith('.r0.json'))) {
      const gen = readJson(path.join(runDir, 'gen', model, f));
      if (gen.result.error || !gen.result.content.trim()) continue;   // nothing to grade; the gate already fails it
      for (const judge of config.judges) {
        jobs.push({ judge, gen, file: path.join(runDir, 'judge', slug(judge), model, `${gen.transcript}.json`) });
      }
    }
  }
  const todo = jobs.filter(j => !fs.existsSync(j.file));
  console.log(`${jobs.length} judgments, ${todo.length} to run`);
  let done = 0, failed = 0;
  await pool(todo, config.concurrency, async (j) => {
    const t = set.get(j.gen.transcript);
    // The judge sees the summary exactly as a user would, and never the model name.
    const res = await judgeSummary(j.judge, { transcript: t.text, serviceType: t.serviceType, tier: t.tier, summary: j.gen.result.content });
    if (res.error) { failed++; console.warn(`  judge failed (${j.judge}): ${res.error}`); }
    else writeJson(j.file, { judge: j.judge, model: j.gen.model, transcript: j.gen.transcript, ...res });
    if (++done % 10 === 0 || done === todo.length) console.log(`  ${done}/${todo.length}`);
  });
  if (failed) console.warn(`${failed} judgments failed; re-run "judge" to retry them`);
}

// ---------- report ----------

function aggregate(runDir, modelSlug) {
  const gens = fs.readdirSync(path.join(runDir, 'gen', modelSlug)).map(f => readJson(path.join(runDir, 'gen', modelSlug, f)));
  const ok = gens.filter(g => g.check);
  const chatDir = path.join(runDir, 'chat', modelSlug);
  const chats = fs.existsSync(chatDir) ? fs.readdirSync(chatDir).map(f => readJson(path.join(chatDir, f))) : [];
  const refTotal = ok.reduce((n, g) => n + g.check.refCount, 0);
  const quoteTotal = ok.reduce((n, g) => n + g.check.quoteCount, 0);

  const judged = {};          // transcript -> judge -> scores
  const perJudge = {};
  for (const judge of config.judges) {
    const dir = path.join(runDir, 'judge', slug(judge), modelSlug);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      const j = readJson(path.join(dir, f));
      (judged[j.transcript] = judged[j.transcript] || {})[judge] = j.scores;
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
  const quality = perTranscript.length
    ? 100 * KEYS.reduce((n, k) => n + config.weights[k] * (scores[k] - 1) / 4, 0)
    : null;
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
    judgedCount: perTranscript.length,
    scores,
    quality,
    worstFaithfulness: allScores.length ? Math.min(...allScores.map(s => s.faithfulness)) : null,
    unsupportedClaimsPerSummary: allScores.length ? mean(allScores.map(s => s.unsupported_claims.length)) : null,
    mainScriptureWrong: allScores.filter(s => s.main_scripture_correct === false).length,
    perJudgeFaithfulness: Object.fromEntries(Object.entries(perJudge).map(([j, ss]) => [j, mean(ss.map(s => s.faithfulness))])),
    perJudgeQuality: Object.fromEntries(Object.entries(perJudge).map(([j, ss]) => [j,
      100 * KEYS.reduce((n, k) => n + config.weights[k] * (mean(ss.map(s => s[k])) - 1) / 4, 0)])),
    failures: {
      missingSections: ok.filter(g => !g.check.sectionsOk).map(g => `${g.transcript.slice(0, 8)}.r${g.rep}: ${g.check.missingSections.join(', ')}`),
      ungroundedRefs: ok.flatMap(g => g.check.refsBookUngrounded.map(r => `${g.transcript.slice(0, 8)}.r${g.rep}: ${r}`)),
    },
  };
}

function applyGates(m, base) {
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
  ];
  if (m.judgedCount) {
    rows.push(['worst single faithfulness score', m.worstFaithfulness, v => v >= g.worstFaithfulnessMin, n2]);
  }
  if (!isBase && base) {
    if (m.judgedCount && base.judgedCount) {
      rows.push(['faithfulness vs baseline', m.scores.faithfulness - base.scores.faithfulness, v => v >= g.faithfulnessVsBaselineMin, sg]);
      rows.push(['scripture accuracy vs baseline', m.scores.scripture - base.scores.scripture, v => v >= g.scriptureVsBaselineMin, sg]);
      rows.push(['quality vs baseline (pts)', m.quality - base.quality, v => v >= g.qualityVsBaselineMin, sg]);
    }
    if (m.costUsd != null && base.costUsd) rows.push(['cost vs baseline', m.costUsd / base.costUsd, v => v <= g.costVsBaselineMax, v => `${v.toFixed(2)}x`]);
  }
  return rows.map(([name, value, test, fmt]) => ({ name, value, shown: value == null ? 'n/a' : fmt(value), pass: value != null && test(value) }));
}

const f2 = (v) => v == null ? 'n/a' : v.toFixed(2);
const p0 = (v) => v == null ? 'n/a' : `${Math.round(v * 100)}%`;

function cmdReport(a) {
  const runDir = path.join(ROOT, 'runs', a.run);
  const manifest = readJson(path.join(DATA, 'manifest.json'));
  const all = fs.readdirSync(path.join(runDir, 'gen')).map(s => aggregate(runDir, s));
  const base = all.find(m => m.model === config.baseline);
  for (const m of all) {
    m.gates = applyGates(m, base);
    m.pass = m.gates.every(x => x.pass);
  }
  all.sort((x, y) => (y.pass - x.pass) || ((y.quality ?? -1) - (x.quality ?? -1)));

  const L = [];
  L.push(`# Model evaluation: ${a.run}`, '');
  L.push(`${manifest.length} transcripts (${manifest.filter(m => m.tier === 'premium').length} premium, ${manifest.filter(m => m.tier === 'basic').length} basic), ${config.repeats} generations each, production prompt. A bare model id uses production parameters unchanged; a [bracketed] label names the request changes. Judges: ${config.judges.join(', ')} (blind, first generation only).`, '');
  L.push('## Result', '');
  L.push('| Model | Verdict | Quality /100 | Faithful | Scripture | Coverage | Sections | Refs section | p95 s | $ / summary |');
  L.push('|---|---|---|---|---|---|---|---|---|---|');
  for (const m of all) {
    const failed = m.gates.filter(x => !x.pass).length;
    const verdict = m === base ? (m.pass ? 'baseline' : `baseline (${failed} gate${failed > 1 ? 's' : ''} failed)`) : m.pass ? 'PASS' : `FAIL (${failed})`;
    L.push(`| ${m.model} | ${verdict} | ${m.quality == null ? 'n/a' : m.quality.toFixed(1)} | ${f2(m.scores.faithfulness)} | ${f2(m.scores.scripture)} | ${f2(m.scores.coverage)} | ${p0(m.sectionsRate)} | ${p0(m.scriptureSectionWithRefRate)} | ${m.latencyP95Ms == null ? 'n/a' : (m.latencyP95Ms / 1000).toFixed(1)} | ${m.costUsd == null ? 'n/a' : m.costUsd.toFixed(4)} |`);
  }
  L.push('', '## Gates', '');
  for (const m of all) {
    L.push(`### ${m.model}`, '');
    for (const x of m.gates) L.push(`- ${x.pass ? 'pass' : '**FAIL**'}: ${x.name} = ${x.shown}`);
    L.push(`- info: faithfulness ${f2(m.scores.faithfulness)} (target ${config.gates.faithfulnessTarget}); references to a book the speaker never named ${p0(m.bookUngroundedRefRate)}; premium sections leaked into basic ${p0(m.premiumLeakRate)}; quotes verbatim ${p0(m.quoteVerbatimRate)}, not found in transcript ${p0(m.quoteFabricatedRate)} (${f2(m.quotesPerSummary)} quotes/summary); references per summary ${f2(m.refsPerSummary)}, chapter found in transcript ${p0(m.chapterGroundedRefRate)}; unsupported claims per summary ${f2(m.unsupportedClaimsPerSummary)}; main scripture judged wrong ${m.mainScriptureWrong}x; truncated ${p0(m.truncatedRate)}; over the 55 s budget ${m.overBudget}x; p50 ${m.latencyP50Ms == null ? 'n/a' : (m.latencyP50Ms / 1000).toFixed(1)} s; avg output tokens ${m.outputTokens == null ? 'n/a' : Math.round(m.outputTokens)}`);
    L.push(`- per judge quality: ${Object.entries(m.perJudgeQuality).map(([j, v]) => `${j.split('/').pop()} ${v.toFixed(1)}`).join(', ') || 'n/a'}`);
    if (m.errors.length) L.push(`- errors (${m.errors.length}): ${[...new Set(m.errors)].slice(0, 3).join(' | ')}`);
    if (m.failures.missingSections.length) L.push(`- missing sections: ${m.failures.missingSections.slice(0, 8).join('; ')}`);
    if (m.failures.ungroundedRefs.length) L.push(`- references to books not in the transcript: ${m.failures.ungroundedRefs.slice(0, 8).join('; ')}`);
    L.push('');
  }
  fs.writeFileSync(path.join(runDir, 'report.md'), L.join('\n'));
  writeJson(path.join(runDir, 'scores.json'), all);
  console.log(L.join('\n'));
}

// ---------- main ----------

(async () => {
  const a = args(process.argv.slice(2));
  const cmd = a._[0];
  if (cmd !== 'pull' && !a.run) throw new Error('--run <name> is required');
  // --judges a,b overrides config (one judge roughly halves the cost of a run).
  if (a.judges) config.judges = a.judges.split(',');
  if (cmd === 'pull') await cmdPull(a);
  else if (cmd === 'run') await cmdRun(a);
  else if (cmd === 'judge') await cmdJudge(a);
  else if (cmd === 'report') cmdReport(a);
  else throw new Error('usage: eval.js pull|run|judge|report (see README.md)');
})().catch((e) => { console.error(`error: ${e.message}`); process.exit(1); });

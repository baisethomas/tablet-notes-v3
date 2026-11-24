#!/usr/bin/env node
'use strict';

// Replacement-model evaluation for the TabletNotes AI endpoints.
// See README.md for the standards this implements.
//
//   node eval.js pull   --source supabase --users <uuid,uuid> [--n 12]
//   node eval.js pull   --source assemblyai --all-users [--n 12]
//   node eval.js run    --run <name> [--models "a;b"] [--repeats 2]
//   node eval.js judge  --run <name> [--judges a,b]
//   node eval.js report --run <name> [--judges a,b]

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const { assemblyKey } = require('./lib/keys');
const { chat, pool } = require('./lib/openrouter');
const { loadSummarize, loadChat } = require('./lib/prompt');
const checks = require('./lib/checks');
const { judgeSummary, judgeOffTopic } = require('./lib/judge');
const { slug, sha, readJson, gradable, resolveJudges, loadJudgment, loadPlan, aggregate, applyGates, verdict } = require('./lib/score');

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
const writeJson = (f, d) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(d, null, 2)); };

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
  // The AssemblyAI account holds every user's recordings and cannot be
  // filtered by user, so this source needs the same explicit decision the
  // supabase source gets from --users.
  if (!a['all-users']) throw new Error('--source assemblyai spans every user\'s recordings; pass --all-users to confirm their transcripts may be sent to third-party models, or use --source supabase --users <uuid,uuid>');
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
  // Record what this run is meant to contain before producing any of it, so
  // `report` can tell a finished run from an interrupted one. --models can
  // add models over several invocations; the transcript set is the manifest's.
  const before = loadPlan(runDir);
  writeJson(path.join(runDir, 'plan.json'), {
    transcripts: set.map(t => t.id),
    repeats,
    chatTranscripts: set.slice(0, config.chatTranscripts).map(t => t.id),
    models: [...new Set([...(before ? before.models : []), ...models(a).map(c => c.label)])],
  });

  let done = 0;
  await pool(todo, config.concurrency, async (j) => {
    if (j.kind === 'summary') {
      // Production aborts the summary at 55 s in total. A reply that arrives
      // later is one production never stores, so it is an error here too.
      const result = await chat(j.model, summarize.messages(j.t), { ...summarize.params, ...j.extra }, { deadlineMs: summarize.timeoutMs });
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
  const judges = a.judges ? a.judges.split(',') : config.judges;
  const set = new Map(loadSet().map(t => [t.id, t]));
  const jobs = [];
  for (const model of fs.readdirSync(path.join(runDir, 'gen'))) {
    for (const f of fs.readdirSync(path.join(runDir, 'gen', model)).filter(f => f.endsWith('.r0.json'))) {
      const gen = readJson(path.join(runDir, 'gen', model, f));
      if (!gradable(gen)) continue;   // nothing to grade; the gate already fails it
      for (const judge of judges) {
        jobs.push({ judge, gen, file: path.join(runDir, 'judge', slug(judge), model, `${gen.transcript}.json`) });
      }
    }
  }
  // Off-topic chat replies the code check accepted: the judges decide whether
  // the reply only redirected or also answered the question.
  const chatRoot = path.join(runDir, 'chat');
  for (const model of fs.existsSync(chatRoot) ? fs.readdirSync(chatRoot) : []) {
    for (const f of fs.readdirSync(path.join(chatRoot, model))) {
      const c = readJson(path.join(chatRoot, model, f));
      if (!c.offTopic.ok) continue;
      for (const judge of judges) {
        jobs.push({ judge, offTopic: c, file: path.join(runDir, 'judge', slug(judge), model, `offtopic.${c.transcript}.json`) });
      }
    }
  }
  const graded = (j) => j.offTopic ? j.offTopic.offTopic.result.content : j.gen.result.content;
  // A judgment is reused only if it graded the text on disk now, so
  // regenerating a model's output also regrades it.
  const todo = jobs.filter(j => !loadJudgment(j.file, graded(j)));
  console.log(`${jobs.length} judgments, ${todo.length} to run`);
  writeJson(path.join(runDir, 'judges.json'), judges);   // report reads this
  let done = 0, failed = 0;
  await pool(todo, config.concurrency, async (j) => {
    if (j.offTopic) {
      const res = await judgeOffTopic(j.judge, { question: OFF_TOPIC, reply: graded(j) });
      if (res.error) { failed++; console.warn(`  judge failed (${j.judge}): ${res.error}`); }
      else writeJson(j.file, { judge: j.judge, model: j.offTopic.model, transcript: j.offTopic.transcript, summarySha: sha(graded(j)), ...res });
      if (++done % 10 === 0 || done === todo.length) console.log(`  ${done}/${todo.length}`);
      return;
    }
    const t = set.get(j.gen.transcript);
    // The judge sees the summary exactly as a user would, and never the model name.
    const res = await judgeSummary(j.judge, { transcript: t.text, serviceType: t.serviceType, tier: t.tier, summary: j.gen.result.content });
    if (res.error) { failed++; console.warn(`  judge failed (${j.judge}): ${res.error}`); }
    else writeJson(j.file, { judge: j.judge, model: j.gen.model, transcript: j.gen.transcript, summarySha: sha(j.gen.result.content), ...res });
    if (++done % 10 === 0 || done === todo.length) console.log(`  ${done}/${todo.length}`);
  });
  if (failed) console.warn(`${failed} judgments failed; re-run "judge" to retry them (the report stays INCOMPLETE until they exist)`);
}

// ---------- report ----------

const f2 = (v) => v == null ? 'n/a' : v.toFixed(2);
const p0 = (v) => v == null ? 'n/a' : `${Math.round(v * 100)}%`;

function cmdReport(a) {
  const runDir = path.join(ROOT, 'runs', a.run);
  const manifest = readJson(path.join(DATA, 'manifest.json'));
  const judges = resolveJudges(runDir, config, a.judges ? a.judges.split(',') : null);
  const plan = loadPlan(runDir);
  // Every model the run planned, even one with no output at all yet.
  const slugs = [...new Set([...fs.readdirSync(path.join(runDir, 'gen')), ...(plan ? plan.models.map(slug) : [])])];
  const all = slugs.map(s => aggregate(runDir, s, config, judges, plan));
  const base = all.find(m => m.model === config.baseline);
  for (const m of all) {
    m.gates = applyGates(m, base, config);
    m.pass = m.gates.every(x => x.pass);
    m.verdict = verdict(m, m === base);
  }
  all.sort((x, y) => (y.pass - x.pass) || ((y.quality ?? -1) - (x.quality ?? -1)));

  const L = [];
  L.push(`# Model evaluation: ${a.run}`, '');
  L.push(`${manifest.length} transcripts (${manifest.filter(m => m.tier === 'premium').length} premium, ${manifest.filter(m => m.tier === 'basic').length} basic), ${plan ? plan.repeats : config.repeats} generations each, production prompt. A bare model id uses production parameters unchanged; a [bracketed] label names the request changes. Judges: ${judges.join(', ')} (blind, first generation only).`, '');
  L.push('## Result', '');
  L.push('| Model | Verdict | Quality /100 | Faithful | Scripture | Coverage | Sections | Refs section | p95 s | $ / summary |');
  L.push('|---|---|---|---|---|---|---|---|---|---|');
  for (const m of all) {
    L.push(`| ${m.model} | ${m.verdict} | ${m.quality == null ? 'n/a' : m.quality.toFixed(1)} | ${f2(m.scores.faithfulness)} | ${f2(m.scores.scripture)} | ${f2(m.scores.coverage)} | ${p0(m.sectionsRate)} | ${p0(m.scriptureSectionWithRefRate)} | ${m.latencyP95Ms == null ? 'n/a' : (m.latencyP95Ms / 1000).toFixed(1)} | ${m.costUsd == null ? 'n/a' : m.costUsd.toFixed(4)} |`);
  }
  L.push('', '## Gates', '');
  for (const m of all) {
    L.push(`### ${m.model}`, '');
    for (const x of m.gates) L.push(`- ${x.pass ? 'pass' : x.evidence ? '**MISSING**' : '**FAIL**'}: ${x.name} = ${x.shown}`);
    L.push(`- info: faithfulness ${f2(m.scores.faithfulness)} (target ${config.gates.faithfulnessTarget}); references to a book the speaker never named ${p0(m.bookUngroundedRefRate)}; premium sections leaked into basic ${p0(m.premiumLeakRate)}; quotes verbatim ${p0(m.quoteVerbatimRate)}, not found in transcript ${p0(m.quoteFabricatedRate)} (${f2(m.quotesPerSummary)} quotes/summary); references per summary ${f2(m.refsPerSummary)}, chapter found in transcript ${p0(m.chapterGroundedRefRate)}; unsupported claims per summary ${f2(m.unsupportedClaimsPerSummary)}; main scripture judged wrong ${m.mainScriptureWrong}x; truncated ${p0(m.truncatedRate)}; over the 55 s budget ${m.overBudget}x; p50 ${m.latencyP50Ms == null ? 'n/a' : (m.latencyP50Ms / 1000).toFixed(1)} s; avg output tokens ${m.outputTokens == null ? 'n/a' : Math.round(m.outputTokens)}`);
    L.push(`- per judge quality: ${Object.entries(m.perJudgeQuality).map(([j, v]) => `${j.split('/').pop()} ${v.toFixed(1)}`).join(', ') || 'n/a'}`);
    if (m.errors.length) L.push(`- errors (${m.errors.length}): ${[...new Set(m.errors)].slice(0, 3).join(' | ')}`);
    if (m.failures.missingSections.length) L.push(`- missing sections: ${m.failures.missingSections.slice(0, 8).join('; ')}`);
    if (m.failures.offTopic.length) L.push(`- off-topic replies that failed: ${m.failures.offTopic.slice(0, 8).join('; ')}`);
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
  if (cmd === 'pull') await cmdPull(a);
  else if (cmd === 'run') await cmdRun(a);
  else if (cmd === 'judge') await cmdJudge(a);
  else if (cmd === 'report') cmdReport(a);
  else throw new Error('usage: eval.js pull|run|judge|report (see README.md)');
})().catch((e) => { console.error(`error: ${e.message}`); process.exit(1); });

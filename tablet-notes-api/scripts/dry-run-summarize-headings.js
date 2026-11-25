#!/usr/bin/env node
/**
 * TAB-120 heading dry-run. Calls gpt-4o-mini with the production summarize
 * prompt and the one-retry heading validator. Does not write to prod, does
 * not call Netlify, and does not print secrets.
 *
 *   OPENAI_API_KEY=... node scripts/dry-run-summarize-headings.js \
 *     --transcript /path/to/transcript.txt --runs 20
 *
 * Default transcript: the four sentences already committed in
 * TabletNotes/TabletNotes/Utils/AppStoreScreenshotSeed.swift ("Hope That
 * Holds"). For the 20/20 acceptance, pass a real sermon transcript and do
 * not commit it.
 *
 * Headings checked: Main Scripture Text, Brief Summary, Key Points,
 * Memorable Elements, Scripture References (aliases as in SummaryDocument).
 */

'use strict';

const fs = require('fs');
const path = require('path');
const {
  REQUIRED_HEADINGS,
  missingRequiredHeadings,
  completeWithHeadingRetry,
  buildRetryUserMessage
} = require('../netlify/functions/utils/summaryFormat');
const { buildSummarizeSystemPrompt } = require('../netlify/functions/utils/summarizePrompt');

// Already in the repo (AppStoreScreenshotSeed.swift). Not a live sermon.
const SEED_TRANSCRIPT = [
  "When Paul writes that all things work together for good, he is calling us to trust God's hands even before we understand the story.",
  'Hope is not denial. Hope is disciplined remembrance.',
  "It looks back at God's faithfulness and carries courage into the next step.",
  'Romans 8:28 becomes more than a verse on a page. It becomes a way to pray, listen, and serve.'
].join('\n\n');

function parseArgs(argv) {
  const args = { runs: 20, transcript: null, tier: 'basic', serviceType: 'Sermon' };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    const val = argv[i + 1];
    if (key === '--runs') { args.runs = Number(val); i++; }
    else if (key === '--transcript') { args.transcript = val; i++; }
    else if (key === '--tier') { args.tier = val; i++; }
    else if (key === '--serviceType') { args.serviceType = val; i++; }
    else if (key === '--help' || key === '-h') { args.help = true; }
  }
  return args;
}

function loadTranscript(specified) {
  if (!specified) {
    return {
      text: SEED_TRANSCRIPT,
      source: 'AppStoreScreenshotSeed.swift (default; already in the repo)'
    };
  }
  const resolved = path.resolve(specified);
  return {
    text: fs.readFileSync(resolved, 'utf8'),
    source: resolved
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(`Usage: node scripts/dry-run-summarize-headings.js [--transcript PATH] [--runs N]
No prod writes. Requires OPENAI_API_KEY. Never prints the key.
Headings: ${REQUIRED_HEADINGS.join(', ')}`);
    process.exit(0);
  }

  if (!process.env.OPENAI_API_KEY) {
    console.error(
      'skip: OPENAI_API_KEY is not set; this dry-run needs a live model call. ' +
      'Run locally with a real transcript (do not commit it): ' +
      'cd tablet-notes-api && OPENAI_API_KEY=... node scripts/dry-run-summarize-headings.js --transcript /path/to/transcript.txt --runs 20. ' +
      `Headings checked: ${REQUIRED_HEADINGS.join(', ')}. ` +
      'Transcript source: a real sermon transcript on disk (for the 20/20 acceptance); ' +
      'omit --transcript to use the four sentences already in AppStoreScreenshotSeed.swift. ' +
      'No prod writes.'
    );
    process.exit(2);
  }

  let OpenAI;
  try {
    OpenAI = require('openai');
  } catch (err) {
    console.error('skip: the openai package is not installed; run npm install in tablet-notes-api, then retry the dry-run.');
    process.exit(2);
  }

  const { text, source } = loadTranscript(args.transcript);
  if (!text || text.trim().length < 50) {
    console.error('Transcript is too short for summarization (need at least 50 characters).');
    process.exit(2);
  }

  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY }); // key never printed
  const system = buildSummarizeSystemPrompt({
    userTier: args.tier,
    serviceType: args.serviceType
  });
  const baseMessages = [
    { role: 'system', content: system },
    { role: 'user', content: `Please summarize this ${args.serviceType} text: ${text}` }
  ];

  let passed = 0;
  const failures = [];

  console.log(`dry-run-summarize-headings: runs=${args.runs} source=${source}`);
  console.log(`headings: ${REQUIRED_HEADINGS.join(', ')}`);
  console.log('prod writes: none');

  for (let i = 1; i <= args.runs; i++) {
    let firstContent = '';
    const result = await completeWithHeadingRetry({
      generate: async (attempt) => {
        const messages = attempt === 1
          ? baseMessages
          : [
              ...baseMessages,
              { role: 'assistant', content: firstContent },
              { role: 'user', content: buildRetryUserMessage(missingRequiredHeadings(firstContent)) }
            ];
        const completion = await openai.chat.completions.create({
          model: 'gpt-4o-mini',
          messages,
          max_tokens: 2000,
          temperature: 0.7
        });
        const content = completion.choices[0].message.content || '';
        if (attempt === 1) firstContent = content;
        return content;
      }
    });
    const missing = missingRequiredHeadings(result.content);
    const ok = missing.length === 0;
    if (ok) passed += 1;
    else failures.push({ run: i, missing, retried: result.retried });
    console.log(
      `run ${i}/${args.runs}: ${ok ? 'PASS' : 'FAIL'} retried=${result.retried}` +
      (ok ? '' : ` missing=${missing.join('|')}`)
    );
  }

  console.log(`result: ${passed}/${args.runs} passed`);
  if (failures.length) {
    console.log('failures:');
    for (const f of failures) {
      console.log(`  run ${f.run} retried=${f.retried} missing=${f.missing.join('|')}`);
    }
  }
  process.exit(passed === args.runs ? 0 : 1);
}

main().catch((err) => {
  console.error('dry-run failed:', err && err.message ? err.message : 'unknown error');
  process.exit(1);
});

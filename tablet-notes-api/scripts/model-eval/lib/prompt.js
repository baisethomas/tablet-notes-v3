'use strict';

// The eval must send exactly what production sends. Rather than keep a second
// copy of the prompts (which would drift), take them from production: the
// summarize system prompt from the module summarize.js itself calls, the rest
// read out of the live function source. Every extraction asserts on a literal
// anchor and throws if the function's shape changed, so a silent mismatch is
// impossible.

const fs = require('node:fs');
const path = require('node:path');
const { API_ROOT } = require('./keys');
const { Validator, LIMITS } = require(path.join(API_ROOT, 'netlify/functions/utils/validator'));
const { buildSummarizeSystemPrompt } = require(path.join(API_ROOT, 'netlify/functions/utils/summarizePrompt'));

const FN = path.join(API_ROOT, 'netlify', 'functions');

function mustMatch(src, re, what) {
  const m = src.match(re);
  if (!m) throw new Error(`prompt extraction failed: ${what}. The function changed; update lib/prompt.js.`);
  return m;
}

function render(template, vars) {
  // The source is a JS template literal; evaluate it with the same variable
  // names. Only `template`, which is this repository's own function source,
  // becomes code. The values are passed as arguments, so a value such as a
  // service type reading "${process.exit()}" is interpolated as that text and
  // never evaluated (pinned in __tests__/prompt.test.js).
  const names = Object.keys(vars);
  // eslint-disable-next-line no-new-func
  return new Function(...names, 'return `' + template + '`;')(...names.map(n => vars[n]));
}

function loadSummarize() {
  const src = fs.readFileSync(path.join(FN, 'summarize.js'), 'utf8');
  // Since TAB-120 the system prompt lives in utils/summarizePrompt.js; check
  // summarize.js still builds its system message from it, with these inputs.
  mustMatch(src, /role:\s*"system",\s*content:\s*buildSummarizeSystemPrompt\(\{ userTier, serviceType: actualServiceType \}\)/, 'summarize system prompt');
  mustMatch(src, /content:\s*`Please summarize this \$\{actualServiceType\} text: \$\{sanitizedText\}`/, 'summarize user message');
  mustMatch(src, /const maxTokens = length === 'short' \? 1000 : length === 'long' \? 3000 : 2000;/, 'summarize max_tokens');
  mustMatch(src, /const temperature = tone === 'formal' \? 0\.3 : tone === 'academic' \? 0\.2 : 0\.7;/, 'summarize temperature');
  mustMatch(src, /max_tokens: maxTokens,\s*temperature\b/, 'summarize request parameters');
  const prodModel = mustMatch(src, /openai\.chat\.completions\.create\(\{\s*model:\s*['"]([^'"]+)['"]/, 'summarize model')[1];

  return {
    prodModel,
    // Defaults the iOS client gets (it sends only text + serviceType):
    // length=medium -> 2000 tokens, tone=conversational -> 0.7.
    params: { max_tokens: 2000, temperature: 0.7 },
    timeoutMs: 55000,
    // The eval sends this first request only. Production (TAB-120) asks once
    // more when the first reply lacks a required heading; a candidate here
    // gets no second attempt, so the format gates are the stricter reading.
    messages({ text, serviceType, tier }) {
      const sanitizedText = Validator.sanitizeLLMText(text, { maxLength: LIMITS.SUMMARY_TEXT_LENGTH });
      return [
        { role: 'system', content: buildSummarizeSystemPrompt({ userTier: tier, serviceType }) },
        { role: 'user', content: `Please summarize this ${serviceType} text: ${sanitizedText}` },
      ];
    },
  };
}

function loadChat() {
  const src = fs.readFileSync(path.join(FN, 'chat.js'), 'utf8');
  const system = mustMatch(src, /const SYSTEM_PROMPT = `([\s\S]*?)`;/, 'chat system prompt')[1];
  const qTpl = mustMatch(src, /content:\s*`(Generate \$\{count\} thought-provoking questions[\s\S]*?)`,/, 'question prompt')[1];
  mustMatch(src, /content:\s*`Sermon context:\\n\$\{contextText\}\\n\\nGenerate \$\{count\} questions\.`/, 'question user message');

  // Mirrors buildContextText in chat.js.
  const contextText = (c) => {
    let t = `Title: ${c.title || 'Unknown'}\nService Type: ${c.serviceType || 'Unknown'}\nDate: ${c.date || 'Unknown'}\n`;
    if (c.speaker) t += `Speaker: ${c.speaker}\n`;
    if (c.summary) t += `\nSummary:\n${c.summary}\n`;
    if (c.transcript) t += `\nTranscript:\n${c.transcript}\n`;
    return t;
  };

  return {
    questions: {
      params: { temperature: 0.7, max_tokens: 500, response_format: { type: 'json_object' } },
      messages(context, count = 3) {
        return [
          { role: 'system', content: render(qTpl, { count }) },
          { role: 'user', content: `Sermon context:\n${contextText(context)}\n\nGenerate ${count} questions.` },
        ];
      },
    },
    chat: {
      params: { temperature: 0.7, max_tokens: 1000 },
      messages(context, userMessage) {
        return [
          { role: 'system', content: `${system}\n\nCurrent sermon context:\n${contextText(context)}` },
          { role: 'user', content: userMessage },
        ];
      },
    },
  };
}

module.exports = { loadSummarize, loadChat, render };

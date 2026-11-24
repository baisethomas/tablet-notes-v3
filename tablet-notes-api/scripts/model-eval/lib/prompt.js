'use strict';

// The eval must send exactly what production sends. Rather than keep a second
// copy of the prompts (which would drift), read them out of the live function
// source. Every extraction asserts on a literal anchor and throws if the
// function's shape changed, so a silent mismatch is impossible.

const fs = require('node:fs');
const path = require('node:path');
const { API_ROOT } = require('./keys');
const { Validator, LIMITS } = require(path.join(API_ROOT, 'netlify/functions/utils/validator'));

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
  const tpl = mustMatch(src, /role:\s*"system",\s*content:\s*`(# Tiered Sermon Summary System Prompt[\s\S]*?)`\s*\},/, 'summarize system prompt')[1];
  mustMatch(src, /content:\s*`Please summarize this \$\{actualServiceType\} text: \$\{sanitizedText\}`/, 'summarize user message');
  mustMatch(src, /max_tokens:\s*length === 'short' \? 1000 : length === 'long' \? 3000 : 2000/, 'summarize max_tokens');
  mustMatch(src, /temperature:\s*tone === 'formal' \? 0\.3 : tone === 'academic' \? 0\.2 : 0\.7/, 'summarize temperature');
  const prodModel = mustMatch(src, /model:\s*"([^"]+)"/, 'summarize model')[1];

  return {
    prodModel,
    // Defaults the iOS client gets (it sends only text + serviceType):
    // length=medium -> 2000 tokens, tone=conversational -> 0.7.
    params: { max_tokens: 2000, temperature: 0.7 },
    timeoutMs: 55000,
    messages({ text, serviceType, tier }) {
      const sanitizedText = Validator.sanitizeLLMText(text, { maxLength: LIMITS.SUMMARY_TEXT_LENGTH });
      return [
        { role: 'system', content: render(tpl, { userTier: tier, actualServiceType: serviceType }) },
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

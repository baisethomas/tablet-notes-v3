'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { render, loadSummarize, loadChat } = require('../lib/prompt');

test('a template is rendered with its variables', () => {
  assert.equal(render('Tier: ${userTier}\\nType: ${actualServiceType}', { userTier: 'basic', actualServiceType: 'Sermon' }), 'Tier: basic\nType: Sermon');
});

// A service type comes from a database row. It must reach the prompt as the
// text it is, whatever it looks like.
const HOSTILE = [
  '${globalThis.__modelEvalPwned = true}',
  '${process.exit(3)}',
  '`; globalThis.__modelEvalPwned = true; `',
  '` + (globalThis.__modelEvalPwned = true) + `',
  '\\`${1/0}',
  '${userTier}',
];

test('a value that looks like code is interpolated as text and never run', () => {
  for (const value of HOSTILE) {
    delete globalThis.__modelEvalPwned;
    const out = render('Service: ${actualServiceType} (${userTier})', { actualServiceType: value, userTier: 'basic' });
    assert.equal(out, `Service: ${value} (basic)`);
    assert.equal(globalThis.__modelEvalPwned, undefined, value);
  }
});

test("the production summary prompt carries a hostile service type as text", () => {
  delete globalThis.__modelEvalPwned;
  const value = '${globalThis.__modelEvalPwned = true}';
  const [system, user] = loadSummarize().messages({ text: 'In the beginning. '.repeat(50), serviceType: value, tier: 'premium' });
  assert.ok(system.content.startsWith('# Tiered Sermon Summary System Prompt'));
  assert.ok(system.content.includes(value) || user.content.includes(value));
  assert.ok(user.content.includes(value));
  assert.equal(globalThis.__modelEvalPwned, undefined);
});

test('the prompts and parameters are read from the production functions', () => {
  const s = loadSummarize();
  assert.deepEqual(s.params, { max_tokens: 2000, temperature: 0.7 });
  assert.equal(s.timeoutMs, 55000);
  assert.equal(s.prodModel, 'gpt-4o-mini');
  // The system message is the one production builds, including the TAB-120
  // rule that the Scripture References heading is always present.
  const { buildSummarizeSystemPrompt } = require('../../../netlify/functions/utils/summarizePrompt');
  const { MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION } = require('../../../netlify/functions/utils/summaryFormat');
  const [system] = s.messages({ text: 'In the beginning. '.repeat(50), serviceType: 'Bible Study', tier: 'basic' });
  assert.equal(system.content, buildSummarizeSystemPrompt({ userTier: 'basic', serviceType: 'Bible Study' }));
  assert.ok(system.content.includes(MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION));
  const c = loadChat();
  assert.equal(c.questions.params.max_tokens, 500);
  assert.equal(c.chat.params.max_tokens, 1000);
  const q = c.questions.messages({ title: 't', serviceType: '${process.exit(3)}', transcript: 'x' }, 3);
  assert.match(q[0].content, /^Generate 3 thought-provoking questions/);
  assert.ok(q[1].content.includes('${process.exit(3)}'));
});

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { candidates, summaryParams, chatParams } = require('../lib/candidates');

const config = {
  baseline: 'vendor/base',
  candidates: [
    'vendor/plain',
    { label: 'vendor/big [5000 tok]', model: 'vendor/big', params: { max_tokens: 5000 } },
    { label: 'vendor/quiet [reasoning off, 4000 tok]', model: 'vendor/quiet', params: { reasoning: { enabled: false }, max_tokens: 4000 }, chatParams: { reasoning: { enabled: false } } },
  ],
};
const SUMMARY = { max_tokens: 2000, temperature: 0.7 };
const QUESTIONS = { temperature: 0.7, max_tokens: 500, response_format: { type: 'json_object' } };
const CHAT = { temperature: 0.7, max_tokens: 1000 };
const by = (label) => candidates(config).find(c => c.label === label);

test('the baseline comes first and a bare id uses production params everywhere', () => {
  const all = candidates(config);
  assert.deepEqual(all.map(c => c.label), ['vendor/base', 'vendor/plain', 'vendor/big [5000 tok]', 'vendor/quiet [reasoning off, 4000 tok]']);
  assert.deepEqual(summaryParams(SUMMARY, by('vendor/plain')), SUMMARY);
  assert.deepEqual(chatParams(CHAT, by('vendor/plain')), CHAT);
});

test("a candidate's summary params do not reach the chat calls", () => {
  const big = by('vendor/big [5000 tok]');
  assert.equal(summaryParams(SUMMARY, big).max_tokens, 5000);
  assert.deepEqual(chatParams(QUESTIONS, big), QUESTIONS);
  assert.deepEqual(chatParams(CHAT, big), CHAT);
});

test('chatParams reach the chat calls and leave the production caps alone', () => {
  const quiet = by('vendor/quiet [reasoning off, 4000 tok]');
  assert.deepEqual(summaryParams(SUMMARY, quiet), { max_tokens: 4000, temperature: 0.7, reasoning: { enabled: false } });
  assert.deepEqual(chatParams(QUESTIONS, quiet), { ...QUESTIONS, reasoning: { enabled: false } });
  assert.equal(chatParams(CHAT, quiet).max_tokens, 1000);
});

test('--models selects by label', () => {
  assert.deepEqual(candidates(config, ['vendor/big [5000 tok]', 'vendor/base']).map(c => c.model), ['vendor/base', 'vendor/big']);
});

test('a --models label that matches no candidate is refused, not run as nothing', () => {
  assert.throws(() => candidates(config, ['vendor/bgi [5000 tok]']), /names no candidate in config\.json: "vendor\/bgi \[5000 tok\]"/);
  // One good label does not excuse a bad one.
  assert.throws(() => candidates(config, ['vendor/plain', 'nope']), /"nope"/);
  assert.throws(() => candidates(config, []), /none given/);
  // A model id is not a label when the candidate has its own label.
  assert.throws(() => candidates(config, ['vendor/big']), /"vendor\/big"/);
});

test('no candidate in config.json changes a chat token cap', () => {
  const real = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config.json'), 'utf8'));
  for (const c of candidates(real)) {
    assert.equal('max_tokens' in c.chatParams, false, c.label);
    assert.equal(chatParams(QUESTIONS, c).max_tokens, 500, c.label);
    assert.equal(chatParams(CHAT, c).max_tokens, 1000, c.label);
  }
});

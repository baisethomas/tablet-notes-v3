'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

process.env.OPENROUTER_API_KEY = 'test-key-not-real';
const { judgeSummary, judgeOffTopic, parseSummary, parseOffTopic } = require('../lib/judge');

const GOOD = '{"faithfulness":4,"coverage":4,"scripture":5,"focus":4,"clarity":4,"main_scripture_correct":true,"unsupported_claims":[],"missed_points":[],"note":"ok"}';
const GOOD_OFF = '{"redirects":true,"answers_political":false,"answers_financial":false,"note":"declined"}';

// Valid JSON that is not a verdict. The parser slices from the first { to the
// last }, so none of these reaches the field checks; this pins that.
const NOT_VERDICTS = ['null', '[]', '[{"faithfulness":5}]', '"five"', '5', 'true', '', '{', '{}'];

test('a summary verdict parses, with or without a code fence', () => {
  assert.equal(parseSummary(GOOD).faithfulness, 4);
  assert.equal(parseSummary('```json\n' + GOOD + '\n```').scripture, 5);
});

test('JSON that is not a summary verdict returns null instead of throwing', () => {
  for (const s of NOT_VERDICTS) assert.equal(parseSummary(s), null, s);
  assert.equal(parseSummary(GOOD.replace('"faithfulness":4', '"faithfulness":9')), null);
  assert.equal(parseSummary(GOOD.replace('"clarity":4', '"clarity":"high"')), null);
});

test('JSON that is not an off-topic verdict returns null instead of throwing', () => {
  for (const s of NOT_VERDICTS) assert.equal(parseOffTopic(s), null, s);
  assert.equal(parseOffTopic(GOOD_OFF.replace('"redirects":true', '"redirects":"yes"')), null);
});

test('an off-topic verdict passes only when it redirects and answers neither question', () => {
  assert.equal(parseOffTopic(GOOD_OFF).redirectOnly, true);
  assert.equal(parseOffTopic(GOOD_OFF.replace('"answers_financial":false', '"answers_financial":true')).redirectOnly, false);
  assert.equal(parseOffTopic(GOOD_OFF.replace('"answers_political":false', '"answers_political":true')).redirectOnly, false);
  assert.equal(parseOffTopic(GOOD_OFF.replace('"redirects":true', '"redirects":false')).redirectOnly, false);
});

function reply(content) {
  return async () => ({ ok: true, status: 200, json: async () => ({ choices: [{ message: { content }, finish_reason: 'stop' }], usage: { cost: 0.01 } }) });
}

test('a judge that answers `null` is an error result, not a crash', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  global.fetch = reply('null');
  const s = await judgeSummary('vendor/judge', { transcript: 'x', serviceType: 'Sermon', tier: 'basic', summary: 'y' });
  assert.deepEqual(s, { error: 'judge returned unparseable output' });
  const o = await judgeOffTopic('vendor/judge', { question: 'q', reply: 'r' });
  assert.deepEqual(o, { error: 'judge returned unparseable output' });
});

test('a judge that answers badly once is asked again', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  let calls = 0;
  global.fetch = async (...args) => reply(++calls === 1 ? 'null' : GOOD)(...args);
  const s = await judgeSummary('vendor/judge', { transcript: 'x', serviceType: 'Sermon', tier: 'basic', summary: 'y' });
  assert.equal(calls, 2);
  assert.equal(s.scores.faithfulness, 4);
});

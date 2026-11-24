'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

process.env.OPENROUTER_API_KEY = 'test-key-not-real';
const { chat, buildBody } = require('../lib/openrouter');

const MESSAGES = [{ role: 'user', content: 'hi' }];

test('candidate params cannot turn off the data-collection denial', () => {
  const body = buildBody('vendor/model', MESSAGES, { provider: { data_collection: 'allow', order: ['x'] }, max_tokens: 5000 });
  assert.equal(body.provider.data_collection, 'deny');
  assert.deepEqual(body.provider.order, ['x']);      // other routing preferences survive
  assert.equal(body.max_tokens, 5000);
});

test('candidate params cannot replace the model, the messages or usage accounting', () => {
  const body = buildBody('vendor/model', MESSAGES, { model: 'other/model', messages: [], usage: { include: false } });
  assert.equal(body.model, 'vendor/model');
  assert.deepEqual(body.messages, MESSAGES);
  assert.deepEqual(body.usage, { include: true });
});

test('with no params the body still denies data collection', () => {
  assert.deepEqual(buildBody('vendor/model', MESSAGES).provider, { data_collection: 'deny' });
});

test('latency covers failed attempts and the backoff, not only the last attempt', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  let calls = 0;
  global.fetch = async () => {
    calls++;
    await wait(150);
    if (calls === 1) return { ok: false, status: 503, json: async () => ({ error: { message: 'overloaded' } }) };
    return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content: 'done' }, finish_reason: 'stop' }], usage: { cost: 0.001 } }) };
  };
  const res = await chat('vendor/model', MESSAGES);
  assert.equal(res.content, 'done');
  assert.equal(res.attempts, 2);
  // 150 ms failed attempt + 2000 ms backoff + 150 ms successful attempt.
  assert.ok(res.latencyMs >= 2250, `latencyMs was ${res.latencyMs}`);
});

test('a total deadline turns a late reply into an error, even when no single attempt was slow', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  let calls = 0;
  // Each attempt fails fast with a retryable error; the 2 s backoff alone
  // carries the call past a 1 s deadline before a second attempt can succeed.
  global.fetch = async () => {
    calls++;
    if (calls === 1) return { ok: false, status: 503, json: async () => ({ error: { message: 'overloaded' } }) };
    return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content: 'too late' }, finish_reason: 'stop' }], usage: {} }) };
  };
  const res = await chat('vendor/model', MESSAGES, {}, { deadlineMs: 1000 });
  assert.match(res.error, /exceeded the 1000ms deadline/);
  assert.equal(res.content, undefined);
  assert.equal(calls, 1);
});

test('a single attempt slower than the deadline is aborted at the deadline', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  global.fetch = (url, { signal }) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve({ ok: true, status: 200, json: async () => ({ choices: [{ message: { content: 'late' }, finish_reason: 'stop' }] }) }), 2000);
    signal.addEventListener('abort', () => { clearTimeout(timer); const e = new Error('aborted'); e.name = 'AbortError'; reject(e); });
  });
  const res = await chat('vendor/model', MESSAGES, {}, { deadlineMs: 300 });
  assert.match(res.error, /exceeded the 300ms deadline/);
  assert.ok(res.latencyMs < 1500, `latencyMs was ${res.latencyMs}`);
});

test('without a deadline a slow reply is still accepted', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  global.fetch = async () => {
    await new Promise(r => setTimeout(r, 400));
    return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content: 'done' }, finish_reason: 'stop' }], usage: {} }) };
  };
  const res = await chat('vendor/model', MESSAGES);
  assert.equal(res.content, 'done');
});

test('a request that never succeeds comes back as an error, not a throw', async (t) => {
  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  global.fetch = async () => ({ ok: false, status: 400, json: async () => ({ error: { message: 'bad request' } }) });
  const res = await chat('vendor/model', MESSAGES);
  assert.equal(res.error, 'bad request');
  assert.equal(res.attempts, 1);
});

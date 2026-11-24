'use strict';

const { openRouterKey } = require('./keys');

const URL = 'https://openrouter.ai/api/v1/chat/completions';

// One chat completion. Never throws: failures come back as { error } so a
// model that cannot do the job is scored, not skipped.
//
// provider.data_collection = 'deny' restricts routing to providers that do not
// retain or train on prompts. Transcripts are user content; a model that is
// only reachable through a logging provider fails here, on purpose.
//
// Candidate params are spread first so they can never replace the model, the
// messages, usage accounting or the data-collection denial.
function buildBody(model, messages, params = {}) {
  return {
    ...params,
    model,
    messages,
    usage: { include: true },
    provider: { ...(params.provider || {}), data_collection: 'deny' },
  };
}

//
// timeoutMs bounds one attempt. deadlineMs bounds the whole call, retries and
// backoff included: it is how a production function with a hard abort is
// modelled, so a response production would have thrown away is an error here.
async function chat(model, messages, params = {}, { timeoutMs = 120000, retries = 2, deadlineMs = null } = {}) {
  const body = buildBody(model, messages, params);

  // latencyMs is what a caller would have waited: every attempt plus the
  // backoff between them. A retry must not make a slow model look fast.
  // Resolved once, before any attempt: a missing key is not a transient
  // failure, so it is reported at once instead of being retried.
  let key;
  try { key = openRouterKey(); } catch (e) { return { error: e.message, latencyMs: 0, attempts: 0 }; }
  const started = Date.now();
  const overDeadline = (attempts) => ({ error: `timeout: exceeded the ${deadlineMs}ms deadline`, latencyMs: Date.now() - started, attempts });
  for (let attempt = 0; ; attempt++) {
    const remaining = deadlineMs == null ? Infinity : deadlineMs - (Date.now() - started);
    if (remaining <= 0) return overDeadline(attempt);
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), Math.min(timeoutMs, remaining));
    try {
      const res = await fetch(URL, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${key}`,
          'content-type': 'application/json',
          'x-title': 'model-eval',
        },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
      // Time the whole body, not the headers: OpenRouter sends headers and
      // keep-alive whitespace long before the completion is finished.
      const json = await res.json().catch(() => null);
      const latencyMs = Date.now() - started;
      // The abort timer stops a body still in flight, but a reply that
      // finishes as the timer is about to fire can get here late. Production
      // would not have stored it, so the clock decides, not the timer.
      if (deadlineMs != null && latencyMs >= deadlineMs) return overDeadline(attempt + 1);
      const err = !res.ok ? (json?.error?.message || `HTTP ${res.status}`) : json?.error?.message;
      if (err) {
        const retryable = res.status === 429 || res.status >= 500;
        if (retryable && attempt < retries) {
          await new Promise(r => setTimeout(r, 2000 * (attempt + 1)));
          continue;
        }
        return { error: String(err).slice(0, 300), status: res.status, latencyMs, attempts: attempt + 1 };
      }
      // A 200 whose body is empty or not a JSON object is a failed request,
      // not a completion with no text.
      if (json === null || typeof json !== 'object') {
        return { error: 'unparseable response body', status: res.status, latencyMs, attempts: attempt + 1 };
      }
      const choice = json.choices?.[0] || {};
      return {
        content: choice.message?.content || '',
        finishReason: choice.finish_reason || null,
        provider: json.provider || null,
        usage: {
          promptTokens: json.usage?.prompt_tokens ?? null,
          completionTokens: json.usage?.completion_tokens ?? null,
          reasoningTokens: json.usage?.completion_tokens_details?.reasoning_tokens ?? null,
          costUsd: json.usage?.cost ?? null,
        },
        latencyMs,
        attempts: attempt + 1,
      };
    } catch (e) {
      const latencyMs = Date.now() - started;
      if (attempt < retries && e.name !== 'AbortError') {
        await new Promise(r => setTimeout(r, 2000 * (attempt + 1)));
        continue;
      }
      if (e.name === 'AbortError' && deadlineMs != null && latencyMs >= deadlineMs) return overDeadline(attempt + 1);
      return { error: e.name === 'AbortError' ? `timeout after ${timeoutMs}ms` : e.message, latencyMs, attempts: attempt + 1 };
    } finally {
      clearTimeout(timer);
    }
  }
}

async function pool(items, concurrency, worker) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await worker(items[i], i);
    }
  }));
  return out;
}

// A pool in which one job throwing does not reject the rest: the throw is
// handed to onError and the other jobs carry on. Returns how many failed.
async function poolSettled(items, concurrency, worker, onError = () => {}) {
  let failed = 0;
  await pool(items, concurrency, async (item, i) => {
    try { await worker(item, i); } catch (e) { failed++; onError(e, item); }
  });
  return failed;
}

module.exports = { chat, pool, poolSettled, buildBody };

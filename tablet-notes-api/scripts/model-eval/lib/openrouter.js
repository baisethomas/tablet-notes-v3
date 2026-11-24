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

async function chat(model, messages, params = {}, { timeoutMs = 120000, retries = 2 } = {}) {
  const body = buildBody(model, messages, params);

  // latencyMs is what a caller would have waited: every attempt plus the
  // backoff between them. A retry must not make a slow model look fast.
  const started = Date.now();
  for (let attempt = 0; ; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(URL, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${openRouterKey()}`,
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
      const err = !res.ok ? (json?.error?.message || `HTTP ${res.status}`) : json?.error?.message;
      if (err) {
        const retryable = res.status === 429 || res.status >= 500;
        if (retryable && attempt < retries) {
          await new Promise(r => setTimeout(r, 2000 * (attempt + 1)));
          continue;
        }
        return { error: String(err).slice(0, 300), status: res.status, latencyMs, attempts: attempt + 1 };
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

module.exports = { chat, pool, buildBody };

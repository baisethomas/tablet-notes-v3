'use strict';

// The models a run tests, and the request each endpoint gets.
//
// A candidate is a model id, or { label, model, params, chatParams } to test
// the same model under a different request. `params` changes the summary
// request only: production caps the two chat calls at 500 and 1,000 tokens,
// and a summary's raised cap must not ride along to them. A change the chat
// calls would also ship with (a reasoning setting, say) is named in
// `chatParams`.

function candidates(config, want) {
  const all = [config.baseline, ...config.candidates].map(c =>
    typeof c === 'string'
      ? { label: c, model: c, params: {}, chatParams: {} }
      : { params: {}, chatParams: {}, ...c });
  if (!want) return all;
  return all.filter(c => want.includes(c.label));
}

const summaryParams = (production, c) => ({ ...production, ...c.params });
const chatParams = (production, c) => ({ ...production, ...c.chatParams });

module.exports = { candidates, summaryParams, chatParams };

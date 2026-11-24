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
  // A label that matches nothing is a typo, not an empty selection: running
  // nothing and exiting cleanly would look like the model had been evaluated.
  const known = new Set(all.map(c => c.label));
  const unknown = want.filter(l => !known.has(l));
  if (unknown.length || !want.length) {
    throw new Error(`--models names no candidate in config.json: ${unknown.map(l => `"${l}"`).join(', ') || '(none given)'}. Labels are: ${[...known].join('; ')}`);
  }
  return all.filter(c => want.includes(c.label));
}

const summaryParams = (production, c) => ({ ...production, ...c.params });
const chatParams = (production, c) => ({ ...production, ...c.chatParams });

module.exports = { candidates, summaryParams, chatParams };

'use strict';

// The parts of the command line that decide something and need no network:
// reading arguments, and choosing which pulled transcripts make the sample.

const crypto = require('node:crypto');

const sha = (s) => crypto.createHash('sha1').update(s).digest('hex');

// `--name value` pairs, bare `--flag` as true, everything else positional.
function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) out[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    else out._.push(argv[i]);
  }
  return out;
}

// The sample: transcripts of sermon length, one per sermon, spread across
// service types. The order depends only on the ids, so the same pull always
// selects the same transcripts.
function selectTranscripts(all, n, { minChars, maxChars }) {
  const seen = new Set();
  const usable = all.filter(t => {
    if (t.text.length < minChars || t.text.length > maxChars) return false;
    const fp = sha(t.text.slice(0, 600).toLowerCase().replace(/\W+/g, ''));
    if (seen.has(fp)) return false;       // the same sermon recorded twice
    seen.add(fp);
    return true;
  });
  // Stratify by service type, deterministic order within a type.
  const groups = new Map();
  for (const t of [...usable].sort((x, y) => sha(x.id).localeCompare(sha(y.id)))) {
    if (!groups.has(t.serviceType)) groups.set(t.serviceType, []);
    groups.get(t.serviceType).push(t);
  }
  const picked = [];
  while (picked.length < n && [...groups.values()].some(g => g.length)) {
    for (const g of groups.values()) if (g.length && picked.length < n) picked.push(g.shift());
  }
  return { usable, picked };
}

// One manifest row. Tiers alternate so both output specs are exercised on the
// same models. The transcript text is not part of the manifest.
const manifestRow = (t, i) => ({
  id: t.id, source: t.source, serviceType: t.serviceType, chars: t.text.length, durationSec: t.durationSec, tier: i % 2 === 0 ? 'premium' : 'basic',
});

module.exports = { args, selectTranscripts, manifestRow };

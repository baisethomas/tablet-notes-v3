'use strict';

// The parts of the command line that decide something and need no network:
// reading arguments, and choosing which pulled transcripts make the sample.

const crypto = require('node:crypto');

const sha = (s) => crypto.createHash('sha1').update(s).digest('hex');

// Flags that take a value, and flags that are switches. Anything else is a
// typo, and a typo that silently changes what runs is worse than an error.
const VALUE_FLAGS = new Set(['run', 'models', 'judges', 'repeats', 'n', 'users', 'source']);
const SWITCHES = new Set(['all-users']);

// `--name value` or `--name=value`, bare switches as true, the rest positional.
// A value flag with no value, or followed by another flag, is refused: write
// `--name=value` for a value that itself begins with dashes.
function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    if (!token.startsWith('--')) { out._.push(token); continue; }
    const eq = token.indexOf('=');
    const name = token.slice(2, eq === -1 ? undefined : eq);
    if (SWITCHES.has(name)) {
      if (eq !== -1) throw new Error(`--${name} takes no value`);
      out[name] = true;
    } else if (VALUE_FLAGS.has(name)) {
      let value;
      if (eq !== -1) value = token.slice(eq + 1);
      else if (argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) value = argv[++i];
      if (value === undefined || value === '') throw new Error(`--${name} needs a value (use --${name}=<value> if it begins with dashes)`);
      out[name] = value;
    } else {
      throw new Error(`unknown option --${name}`);
    }
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

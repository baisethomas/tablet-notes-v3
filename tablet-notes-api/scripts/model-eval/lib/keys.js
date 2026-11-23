'use strict';

// Key resolution for the eval harness. Keys are never written to disk or
// printed. Order: process env, then the owner's local sources.
//
//   ASSEMBLYAI_API_KEY  env, else `netlify env:get` (this dir is netlify-linked)
//   OPENROUTER_API_KEY  env, else the file named by OPENROUTER_ENV_FILE
//                       (default: ~/Dev/openrouter-genmedia/.env)

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const API_ROOT = path.resolve(__dirname, '..', '..', '..');

function fromEnvFile(file, name) {
  if (!fs.existsSync(file)) return null;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const m = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && m[1] === name) return m[2].replace(/^['"]|['"]$/g, '');
  }
  return null;
}

function assemblyKey() {
  if (process.env.ASSEMBLYAI_API_KEY) return process.env.ASSEMBLYAI_API_KEY;
  try {
    const out = execFileSync(
      'netlify',
      ['env:get', 'ASSEMBLYAI_API_KEY', '--context', 'production'],
      { cwd: API_ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }
    );
    const key = out.trim().split('\n').pop().trim();
    if (key) return key;
  } catch (_) { /* fall through */ }
  throw new Error('ASSEMBLYAI_API_KEY not set and `netlify env:get` failed');
}

function openRouterKey() {
  if (process.env.OPENROUTER_API_KEY) return process.env.OPENROUTER_API_KEY;
  const file = process.env.OPENROUTER_ENV_FILE
    || path.join(os.homedir(), 'Dev', 'openrouter-genmedia', '.env');
  const key = fromEnvFile(file, 'OPENROUTER_API_KEY');
  if (key) return key;
  throw new Error(`OPENROUTER_API_KEY not set and not found in ${file}`);
}

module.exports = { assemblyKey, openRouterKey, API_ROOT };

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { fromEnvFile, openRouterKey, assemblyKey } = require('../lib/keys');

// Made-up values. No real key is read or written by these tests.
function envFile(text) {
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'model-eval-keys-')), '.env');
  fs.writeFileSync(f, text);
  return f;
}

function withEnv(vars, fn) {
  const saved = {};
  for (const k of Object.keys(vars)) { saved[k] = process.env[k]; if (vars[k] == null) delete process.env[k]; else process.env[k] = vars[k]; }
  try { return fn(); } finally {
    for (const k of Object.keys(saved)) { if (saved[k] == null) delete process.env[k]; else process.env[k] = saved[k]; }
  }
}

test('an env file is read by exact name, with quotes, export and spacing handled', () => {
  const f = envFile([
    '# comment',
    'OTHER_OPENROUTER_API_KEY=wrong-one',
    'OPENROUTER_API_KEY_OLD=wrong-two',
    'export OPENROUTER_API_KEY = "made-up-value"  ',
    "SINGLE='quoted'",
    'PLAIN=bare',
    '',
  ].join('\n'));
  assert.equal(fromEnvFile(f, 'OPENROUTER_API_KEY'), 'made-up-value');
  assert.equal(fromEnvFile(f, 'SINGLE'), 'quoted');
  assert.equal(fromEnvFile(f, 'PLAIN'), 'bare');
  assert.equal(fromEnvFile(f, 'MISSING'), null);
  assert.equal(fromEnvFile(path.join(os.tmpdir(), 'no-such-dir-model-eval', '.env'), 'PLAIN'), null);
});

test('the OpenRouter key comes from the environment first, then the named file', () => {
  const f = envFile('OPENROUTER_API_KEY=from-file\n');
  withEnv({ OPENROUTER_API_KEY: 'from-env', OPENROUTER_ENV_FILE: f }, () => assert.equal(openRouterKey(), 'from-env'));
  withEnv({ OPENROUTER_API_KEY: null, OPENROUTER_ENV_FILE: f }, () => assert.equal(openRouterKey(), 'from-file'));
});

test('a missing OpenRouter key is an error that names the file and no key', () => {
  const f = envFile('SOMETHING_ELSE=made-up-secret\n');
  withEnv({ OPENROUTER_API_KEY: null, OPENROUTER_ENV_FILE: f }, () => {
    assert.throws(() => openRouterKey(), (e) => e.message.includes(f) && !e.message.includes('made-up-secret'));
  });
});

test('the AssemblyAI key comes from the environment when it is set', () => {
  withEnv({ ASSEMBLYAI_API_KEY: 'from-env' }, () => assert.equal(assemblyKey(), 'from-env'));
});

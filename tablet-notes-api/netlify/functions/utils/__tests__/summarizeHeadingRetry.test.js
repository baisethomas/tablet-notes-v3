const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

// TAB-120 Ternary 2b: completeWithHeadingRetry lives in summaryFormat.js, but
// the retry is only useful if summarize.js actually sends the first response
// back as an assistant message and asks for a rewrite. This runs the handler
// in a child process so the OpenAI / Supabase stubs cannot poison sibling
// tests that require the real clients.

test('summarize.js retries via OpenAI when the first response is narrative', () => {
  const child = path.join(__dirname, 'summarizeHandlerRetry.child.js');
  const result = spawnSync(process.execPath, [child], {
    encoding: 'utf8',
    timeout: 20000,
    env: {
      ...process.env,
      OPENAI_API_KEY: 'test-openai-key',
      SUPABASE_URL: 'https://example.supabase.co',
      SUPABASE_SERVICE_ROLE_KEY: 'test-service-role',
      ASSEMBLYAI_WEBHOOK_SECRET: 'test-internal-secret',
      LOG_LEVEL: 'ERROR'
    }
  });

  assert.equal(result.status, 0, result.stdout + result.stderr);
  const lines = result.stdout.trim().split('\n').filter(Boolean);
  const report = JSON.parse(lines[lines.length - 1]);
  assert.equal(report.statusCode, 200);
  assert.equal(report.callCount, 2);
  assert.equal(report.secondHasAssistantFirstContent, true);
  assert.equal(report.secondHasRetryUserMessage, true);
  assert.equal(report.returnedSectionedSummary, true);
});

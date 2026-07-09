const { test } = require('node:test');
const assert = require('node:assert');
const { deriveStages, buildRunProperties } = require('../agentRunRecorder');

function sampleResult(overrides = {}) {
  return {
    processed: true,
    context: {
      conversationId: 123,
      conversationNumber: 42,
      subject: 'Recording lost after sync',
      url: 'https://secure.helpscout.net/conversation/123/42'
    },
    triage: {
      category: 'bug',
      priority: 1,
      labels: ['support', 'bug'],
      summary: 'Customer lost a recording after sync',
      shouldCreateLinearIssue: true,
      shouldStartEngineeringWork: true
    },
    linearIssue: { identifier: 'TAB-99', url: 'https://linear.app/x/issue/TAB-99' },
    helpScoutDraftReply: { id: 9 },
    subAgentReports: { engineering: {} },
    replyReview: { changed: false, reviewNotes: [] },
    agentError: null,
    ...overrides
  };
}

test('deriveStages marks a clean run all ok with linear created', () => {
  const stages = deriveStages(sampleResult(), { llmEnabled: true });
  assert.strictEqual(
    stages,
    'fetch:ok|triage:ok|llm:ok|subagents:ok|sanitize:ok|linear:ok|draft:ok|note:ok'
  );
});

test('deriveStages marks llm skip when agent disabled and linear skip when no issue', () => {
  const stages = deriveStages(
    sampleResult({ linearIssue: null }),
    { llmEnabled: false }
  );
  assert.match(stages, /llm:skip/);
  assert.match(stages, /linear:skip/);
});

test('deriveStages marks llm fail on agentError and sanitize flag on rewrite', () => {
  const stages = deriveStages(
    sampleResult({ agentError: 'rate limited', replyReview: { changed: true, reviewNotes: ['x'] } }),
    { llmEnabled: true }
  );
  assert.match(stages, /llm:fail/);
  assert.match(stages, /sanitize:flag/);
});

test('deriveStages on thrown workflow marks everything failed', () => {
  const stages = deriveStages(undefined, { error: new Error('boom') });
  assert.match(stages, /^fetch:fail\|triage:fail/);
});

test('buildRunProperties maps triage into Notion properties', () => {
  const props = buildRunProperties({
    result: sampleResult(),
    startedAt: Date.now(),
    durationMs: 1234.6,
    llmEnabled: true
  });

  assert.strictEqual(props.Run.title[0].text.content, '#42 Recording lost after sync');
  assert.strictEqual(props.Status.select.name, 'Processed');
  assert.strictEqual(props.Category.select.name, 'bug');
  assert.strictEqual(props.Priority.select.name, 'Urgent');
  assert.strictEqual(props['Duration (ms)'].number, 1235);
  assert.strictEqual(props.Conversation.url, 'https://secure.helpscout.net/conversation/123/42');
  assert.strictEqual(props['Linear Issue'].url, 'https://linear.app/x/issue/TAB-99');
  assert.strictEqual(props.Error, undefined);
});

test('buildRunProperties marks failed runs and records the error', () => {
  const props = buildRunProperties({
    result: undefined,
    error: new Error('Linear: GraphQL error: team not found'),
    startedAt: Date.now(),
    durationMs: 200,
    llmEnabled: true
  });

  assert.strictEqual(props.Status.select.name, 'Failed');
  assert.match(props.Run.title[0].text.content, /FAILED$/);
  assert.match(props.Error.rich_text[0].text.content, /team not found/);
});

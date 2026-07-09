const test = require('node:test');
const assert = require('node:assert/strict');

const { SupportAgent, normalizeAgentDecision } = require('../supportAgent');

const context = {
  subject: 'Recording disappears',
  customer: {
    firstName: 'Jordan',
    email: 'jordan@example.com'
  },
  latestCustomerMessage: 'My recording disappeared after the app closed.',
  detectedMetadata: {
    osVersion: 'iPadOS 18.5'
  }
};

const fallbackTriage = {
  category: 'bug',
  priority: 1,
  labels: ['support', 'bug', 'data-loss'],
  summary: 'Customer is reporting possible data loss.',
  shouldCreateLinearIssue: true,
  shouldStartEngineeringWork: true
};

test('normalizes a valid agent decision and preserves safe bounds', () => {
  const decision = normalizeAgentDecision({
    category: 'bug',
    priority: 0,
    labels: ['support', 'bug', 'recording', '', 7],
    summary: 'Recording disappears after closing the app.',
    shouldCreateLinearIssue: true,
    shouldStartEngineeringWork: true,
    draftReply: 'Hi Jordan,\n\nThanks for the report.\n\nThanks,\nTablet Notes Support'
  }, fallbackTriage, context);

  assert.equal(decision.triage.priority, 1);
  assert.deepEqual(decision.triage.labels, ['support', 'bug', 'recording']);
  assert.equal(decision.triage.summary, 'Recording disappears after closing the app.');
  assert.match(decision.draftReply, /Hi Jordan/);
});

test('falls back for invalid agent JSON shape', () => {
  const decision = normalizeAgentDecision({
    category: 'not-real',
    priority: 9,
    labels: [],
    summary: '',
    shouldCreateLinearIssue: 'yes',
    shouldStartEngineeringWork: 'no',
    draftReply: ''
  }, fallbackTriage, context);

  assert.equal(decision.triage.category, 'bug');
  assert.equal(decision.triage.priority, 1);
  assert.deepEqual(decision.triage.labels, ['support', 'bug', 'data-loss']);
  assert.match(decision.draftReply, /We're looking into this/);
});

test('SupportAgent asks OpenAI for a JSON decision', async () => {
  const calls = [];
  const openAIClient = {
    chat: {
      completions: {
        create: async (input) => {
          calls.push(input);
          return {
            choices: [{
              message: {
                content: JSON.stringify({
                  category: 'bug',
                  priority: 2,
                  labels: ['support', 'bug'],
                  summary: 'Crash during recording playback.',
                  shouldCreateLinearIssue: true,
                  shouldStartEngineeringWork: true,
                  draftReply: 'Hi Jordan,\n\nThanks, we are investigating this recording issue.\n\nThanks,\nTablet Notes Support'
                })
              }
            }]
          };
        }
      }
    }
  };

  const agent = new SupportAgent({ openAIClient, model: 'test-model' });
  const decision = await agent.analyze(context, fallbackTriage);

  assert.equal(decision.triage.priority, 2);
  assert.equal(decision.triage.summary, 'Crash during recording playback.');
  assert.equal(calls[0].model, 'test-model');
  assert.equal(calls[0].response_format.type, 'json_object');
  assert.match(calls[0].messages[1].content, /Recording disappears/);
});

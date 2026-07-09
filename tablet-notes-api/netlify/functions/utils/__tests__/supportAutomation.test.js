const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const {
  buildHelpScoutDraftReply,
  buildLinearIssueInput,
  buildSupportContext,
  runSupportWorkflow,
  triageSupportContext,
  verifyHelpScoutSignature
} = require('../supportAutomation');

const sampleConversation = {
  id: 123,
  number: 456,
  subject: 'App crashes after recording',
  status: 'active',
  createdAt: '2026-07-07T15:00:00Z',
  customer: {
    id: 789,
    firstName: 'Jordan',
    lastName: 'Lee',
    email: 'jordan@example.com'
  },
  mailbox: {
    id: 42,
    name: 'Tablet Notes Support'
  },
  _links: {
    web: {
      href: 'https://secure.helpscout.net/conversation/123/456'
    }
  },
  _embedded: {
    threads: [
      {
        id: 1,
        type: 'customer',
        body: 'I recorded a sermon and now the app crashes when I open the recording. iPadOS 18.5, Tablet Notes 1.0.2.',
        createdAt: '2026-07-07T15:01:00Z',
        createdBy: { type: 'customer' }
      },
      {
        id: 2,
        type: 'note',
        body: 'Existing internal note should not be treated as customer text.',
        createdAt: '2026-07-07T15:02:00Z',
        createdBy: { type: 'user' }
      }
    ]
  }
};

test('verifies Help Scout webhook signatures with raw body HMAC-SHA1 base64', () => {
  const rawBody = JSON.stringify({ id: 123, subject: 'Help' });
  const secret = 'shared-secret';
  const signature = crypto.createHmac('sha1', secret).update(rawBody).digest('base64');

  assert.equal(verifyHelpScoutSignature(rawBody, signature, secret), true);
  assert.equal(verifyHelpScoutSignature(rawBody, 'bad-signature', secret), false);
});

test('builds a compact support context from a Help Scout conversation', () => {
  const context = buildSupportContext(sampleConversation);

  assert.equal(context.conversationId, 123);
  assert.equal(context.conversationNumber, 456);
  assert.equal(context.subject, 'App crashes after recording');
  assert.equal(context.customer.email, 'jordan@example.com');
  assert.equal(context.latestCustomerMessage, 'I recorded a sermon and now the app crashes when I open the recording. iPadOS 18.5, Tablet Notes 1.0.2.');
  assert.deepEqual(context.detectedMetadata, {
    appVersion: '1.0.2',
    osVersion: 'iPadOS 18.5'
  });
});

test('triages crash and data-loss reports as urgent engineering work', () => {
  const context = buildSupportContext(sampleConversation);
  const triage = triageSupportContext(context);

  assert.equal(triage.category, 'bug');
  assert.equal(triage.priority, 1);
  assert.equal(triage.shouldCreateLinearIssue, true);
  assert.equal(triage.shouldStartEngineeringWork, true);
  assert.deepEqual(triage.labels, ['support', 'bug', 'crash']);
});

test('triages simple how-to questions without creating a Linear issue', () => {
  const context = buildSupportContext({
    ...sampleConversation,
    subject: 'How do I export my notes?',
    _embedded: {
      threads: [
        {
          type: 'customer',
          body: 'How do I export a sermon summary from Tablet Notes?',
          createdAt: '2026-07-07T15:01:00Z',
          createdBy: { type: 'customer' }
        }
      ]
    }
  });

  const triage = triageSupportContext(context);

  assert.equal(triage.category, 'how_to');
  assert.equal(triage.priority, 4);
  assert.equal(triage.shouldCreateLinearIssue, false);
  assert.equal(triage.shouldStartEngineeringWork, false);
});

test('builds a Linear issue input with Help Scout traceability', () => {
  const context = buildSupportContext(sampleConversation);
  const triage = triageSupportContext(context);
  const issue = buildLinearIssueInput(context, triage, {
    teamId: 'team-uuid',
    projectId: 'project-uuid'
  });

  assert.equal(issue.teamId, 'team-uuid');
  assert.equal(issue.projectId, 'project-uuid');
  assert.equal(issue.priority, 1);
  assert.match(issue.title, /\[Support\] App crashes after recording/);
  assert.match(issue.description, /Help Scout: https:\/\/secure\.helpscout\.net\/conversation\/123\/456/);
  assert.match(issue.description, /Customer: Jordan Lee <jordan@example\.com>/);
  assert.match(issue.description, /iPadOS 18\.5/);
});

test('builds a Help Scout draft reply that stays human-reviewable', () => {
  const context = buildSupportContext(sampleConversation);
  const triage = triageSupportContext(context);
  const reply = buildHelpScoutDraftReply(context, triage);

  assert.match(reply, /Hi Jordan/);
  assert.match(reply, /I'm sorry/);
  assert.match(reply, /We're looking into this/);
});

test('runs the support workflow with injected clients', async () => {
  const calls = [];
  const helpScoutClient = {
    getConversation: async (conversationId) => {
      calls.push(['getConversation', conversationId]);
      return sampleConversation;
    },
    createDraftReply: async (conversationId, input) => {
      calls.push(['createDraftReply', conversationId, input.draft, input.customer.id, input.status]);
      return { id: 999 };
    },
    createNote: async (conversationId, input) => {
      calls.push(['createNote', conversationId, input.text]);
      return { id: 1000 };
    }
  };
  const linearClient = {
    createIssue: async (input) => {
      calls.push(['createIssue', input.teamId, input.priority]);
      return { id: 'issue-uuid', identifier: 'TAB-101', url: 'https://linear.app/tabletnotes/issue/TAB-101' };
    }
  };

  const result = await runSupportWorkflow({
    eventName: 'convo.customer.reply.created',
    payload: { id: 123 },
    helpScoutClient,
    linearClient,
    config: {
      linearTeamId: 'team-uuid',
      linearProjectId: 'project-uuid'
    }
  });

  assert.equal(result.processed, true);
  assert.equal(result.triage.category, 'bug');
  assert.equal(result.linearIssue.identifier, 'TAB-101');
  assert.equal(result.helpScoutDraftReply.id, 999);
  assert.deepEqual(calls.map((call) => call[0]), [
    'getConversation',
    'createIssue',
    'createDraftReply',
    'createNote'
  ]);
  assert.equal(calls.find((call) => call[0] === 'createDraftReply')[4], undefined);
});

test('runs the support workflow with agent-generated triage and draft reply', async () => {
  const calls = [];
  const helpScoutClient = {
    getConversation: async () => sampleConversation,
    createDraftReply: async (conversationId, input) => {
      calls.push(['createDraftReply', input.text]);
      return { id: 999 };
    },
    createNote: async (conversationId, input) => {
      calls.push(['createNote', input.text]);
      return { id: 1000 };
    }
  };
  const linearClient = {
    createIssue: async (input) => {
      calls.push(['createIssue', input.priority, input.description]);
      return { id: 'issue-uuid', identifier: 'TAB-102', url: 'https://linear.app/tabletnotes/issue/TAB-102' };
    }
  };
  const supportAgent = {
    analyze: async (context, fallbackTriage) => ({
      triage: {
        ...fallbackTriage,
        category: 'bug',
        priority: 2,
        labels: ['support', 'bug', 'recording'],
        summary: 'Agent identified a recording crash after save.',
        shouldCreateLinearIssue: true,
        shouldStartEngineeringWork: true
      },
      draftReply: 'Hi Jordan,\n\nAgent-written draft.\n\nThanks,\nTablet Notes Support'
    })
  };

  const result = await runSupportWorkflow({
    eventName: 'convo.customer.reply.created',
    payload: { id: 123 },
    helpScoutClient,
    linearClient,
    supportAgent,
    config: {
      linearTeamId: 'team-uuid'
    }
  });

  assert.equal(result.triage.priority, 2);
  assert.equal(result.helpScoutDraftReply.id, 999);
  assert.equal(result.draftReply, 'Hi Jordan,\n\nAgent-written draft.\n\nThanks,\nTablet Notes Support');
  assert.match(calls.find((call) => call[0] === 'createIssue')[2], /Agent identified a recording crash after save/);
});

test('falls back to deterministic triage when the support agent fails', async () => {
  const helpScoutClient = {
    getConversation: async () => sampleConversation,
    createDraftReply: async () => ({ id: 999 }),
    createNote: async () => ({ id: 1000 })
  };
  const linearClient = {
    createIssue: async () => ({ id: 'issue-uuid', identifier: 'TAB-103' })
  };
  const supportAgent = {
    analyze: async () => {
      throw new Error('model unavailable');
    }
  };

  const result = await runSupportWorkflow({
    eventName: 'convo.customer.reply.created',
    payload: { id: 123 },
    helpScoutClient,
    linearClient,
    supportAgent,
    config: {
      linearTeamId: 'team-uuid'
    }
  });

  assert.equal(result.triage.category, 'bug');
  assert.equal(result.agentError, 'model unavailable');
  assert.match(result.draftReply, /We're looking into this/);
});

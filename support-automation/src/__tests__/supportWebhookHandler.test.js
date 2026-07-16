const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { Readable } = require('node:stream');

const { handleSupportWebhook } = require('../supportWebhookHandler');
const { readRawBody } = require('../../api/support-webhook');

test('preserves the raw request bytes used by Help Scout signature verification', async () => {
  const rawBody = '{\n  "id": 123,\n  "subject": "Spacing matters"\n}';
  const request = Readable.from([rawBody]);
  Object.defineProperty(request, 'body', {
    get() {
      throw new Error('parsed body must not be accessed before the raw stream');
    }
  });

  assert.equal(await readRawBody(request), rawBody);
});

test('accepts a signed Help Scout event without invoking unsupported workflows', async () => {
  const rawBody = JSON.stringify({ id: 123 });
  const secret = 'webhook-secret';
  const signature = crypto.createHmac('sha1', secret).update(rawBody).digest('base64');

  const response = await handleSupportWebhook({
    method: 'POST',
    headers: {
      'x-helpscout-event': 'convo.deleted',
      'x-helpscout-signature': signature
    },
    rawBody
  }, {
    env: { HELPSCOUT_WEBHOOK_SECRET: secret }
  });

  assert.equal(response.statusCode, 202);
  assert.deepEqual(JSON.parse(response.body), {
    processed: false,
    reason: 'Ignored Help Scout event: convo.deleted'
  });
});

test('routes a processable event through the configured inbox and Linear team', async () => {
  const rawBody = JSON.stringify({ id: 123 });
  const secret = 'webhook-secret';
  const signature = crypto.createHmac('sha1', secret).update(rawBody).digest('base64');
  let linearTeamId;

  const response = await handleSupportWebhook({
    method: 'POST',
    headers: {
      'x-helpscout-event': 'convo.created',
      'x-helpscout-signature': signature
    },
    rawBody
  }, {
    env: {
      HELPSCOUT_WEBHOOK_SECRET: secret,
      SUPPORT_INBOX_ROUTES: JSON.stringify({
        84: {
          productName: 'Granted AI',
          mailboxName: 'Granted AI Support',
          supportEmail: 'support@grantedai.app',
          supportSignature: 'Granted AI Support',
          agentGuidance: 'Use only details present in the ticket.',
          linearTeamId: 'granted-ai-team'
        }
      })
    },
    helpScoutClient: {
      getConversation: async () => ({
        id: 123,
        number: 456,
        subject: 'App crashes during setup',
        customer: { id: 789, firstName: 'Jordan' },
        mailboxId: 84,
        _embedded: {
          threads: [{
            type: 'customer',
            body: 'The app crashes during setup.',
            createdAt: '2026-07-16T00:00:00Z',
            createdBy: { type: 'customer' }
          }]
        }
      }),
      createDraftReply: async () => ({ id: 900 }),
      createNote: async () => ({ id: 901 })
    },
    linearClient: {
      createIssue: async (input) => {
        linearTeamId = input.teamId;
        return { id: 'issue-id', identifier: 'GRA-1' };
      }
    },
    supportAgent: null,
    recordAgentRun: async () => ({ recorded: false })
  });

  assert.equal(response.statusCode, 202);
  assert.equal(linearTeamId, 'granted-ai-team');
  assert.deepEqual(JSON.parse(response.body), {
    processed: true,
    category: 'bug',
    product: 'Granted AI',
    helpScoutMailbox: 84,
    linearIssue: 'GRA-1',
    helpScoutDraftReply: 900
  });
});

test('processes a how-to ticket without requiring Linear credentials', async () => {
  const rawBody = JSON.stringify({ id: 124 });
  const secret = 'webhook-secret';
  const signature = crypto.createHmac('sha1', secret).update(rawBody).digest('base64');
  let draftCreated = false;

  const response = await handleSupportWebhook({
    method: 'POST',
    headers: {
      'x-helpscout-event': 'convo.created',
      'x-helpscout-signature': signature
    },
    rawBody
  }, {
    env: {
      HELPSCOUT_WEBHOOK_SECRET: secret,
      SUPPORT_INBOX_ROUTES: JSON.stringify({
        84: {
          productName: 'Granted AI',
          mailboxName: 'Granted AI Support',
          supportEmail: 'support@grantedai.app',
          supportSignature: 'Granted AI Support',
          agentGuidance: 'Use only details present in the ticket.',
          linearTeamId: 'granted-ai-team'
        }
      })
    },
    helpScoutClient: {
      getConversation: async () => ({
        id: 124,
        subject: 'How do I export?',
        primaryCustomer: { id: 789, first: 'Jordan' },
        mailboxId: 84,
        _embedded: {
          threads: [{
            type: 'customer',
            body: 'How do I export my notes?',
            createdAt: '2026-07-16T00:00:00Z',
            createdBy: { type: 'customer' }
          }]
        }
      }),
      createDraftReply: async () => {
        draftCreated = true;
        return { id: 902 };
      },
      createNote: async () => ({ id: 903 })
    },
    supportAgent: null,
    recordAgentRun: async () => ({ recorded: false })
  });

  assert.equal(response.statusCode, 202);
  assert.equal(JSON.parse(response.body).category, 'how_to');
  assert.equal(draftCreated, true);
});

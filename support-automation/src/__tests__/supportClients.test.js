const test = require('node:test');
const assert = require('node:assert/strict');

const { HelpScoutClient } = require('../helpScoutClient');
const { LinearClient } = require('../linearClient');

test('HelpScoutClient authenticates with client credentials and fetches embedded threads', async () => {
  const calls = [];
  const client = new HelpScoutClient({
    appId: 'app-id',
    appSecret: 'app-secret',
    fetchImpl: async (url, options) => {
      calls.push({ url, options });

      if (url.endsWith('/oauth2/token')) {
        return jsonResponse({ access_token: 'token-1', expires_in: 172800 });
      }

      return jsonResponse({ id: 123, _embedded: { threads: [] } });
    }
  });

  const conversation = await client.getConversation(123);

  assert.equal(conversation.id, 123);
  assert.equal(calls[0].url, 'https://api.helpscout.net/v2/oauth2/token');
  assert.equal(calls[0].options.body.toString(), 'grant_type=client_credentials&client_id=app-id&client_secret=app-secret');
  assert.equal(calls[1].url, 'https://api.helpscout.net/v2/conversations/123?embed=threads');
  assert.equal(calls[1].options.headers.Authorization, 'Bearer token-1');
});

test('HelpScoutClient creates a draft reply with the Help Scout customer id', async () => {
  const calls = [];
  const client = new HelpScoutClient({
    appId: 'app-id',
    appSecret: 'app-secret',
    fetchImpl: async (url, options) => {
      calls.push({ url, options });

      if (url.endsWith('/oauth2/token')) {
        return jsonResponse({ access_token: 'token-1', expires_in: 172800 });
      }

      return createdResponse('999');
    }
  });

  const result = await client.createDraftReply(123, {
    customer: { id: 789 },
    text: 'Draft text',
    status: 'pending'
  });

  const replyRequest = calls[1];
  assert.equal(result.id, '999');
  assert.equal(replyRequest.url, 'https://api.helpscout.net/v2/conversations/123/reply');
  assert.deepEqual(JSON.parse(replyRequest.options.body), {
    customer: { id: 789 },
    text: 'Draft text',
    draft: true,
    status: 'pending'
  });
});

test('LinearClient creates an issue with a GraphQL mutation and raw API-key auth header', async () => {
  const calls = [];
  const client = new LinearClient({
    apiKey: 'lin_api_key',
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse({
        data: {
          issueCreate: {
            success: true,
            issue: {
              id: 'issue-id',
              identifier: 'TAB-123',
              title: 'Support issue',
              url: 'https://linear.app/tabletnotes/issue/TAB-123'
            }
          }
        }
      });
    }
  });

  const issue = await client.createIssue({
    teamId: 'team-id',
    title: 'Support issue',
    description: 'Details',
    priority: 1
  });

  const requestBody = JSON.parse(calls[0].options.body);
  assert.equal(issue.identifier, 'TAB-123');
  assert.equal(calls[0].url, 'https://api.linear.app/graphql');
  assert.equal(calls[0].options.headers.Authorization, 'lin_api_key');
  assert.match(requestBody.query, /mutation IssueCreate/);
  assert.deepEqual(requestBody.variables.input, {
    teamId: 'team-id',
    title: 'Support issue',
    description: 'Details',
    priority: 1
  });
});

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: new Map(),
    json: async () => body,
    text: async () => JSON.stringify(body)
  };
}

function createdResponse(resourceId) {
  return {
    ok: true,
    status: 201,
    headers: {
      get: (key) => key.toLowerCase() === 'resource-id' ? resourceId : null
    },
    json: async () => ({}),
    text: async () => ''
  };
}

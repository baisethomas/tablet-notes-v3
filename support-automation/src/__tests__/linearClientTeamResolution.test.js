const test = require('node:test');
const assert = require('node:assert/strict');

const { LinearClient } = require('../linearClient');

test('LinearClient resolves a team key before creating an issue', async () => {
  const calls = [];
  const client = new LinearClient({
    apiKey: 'lin_api_key',
    fetchImpl: async (url, options) => {
      const body = JSON.parse(options.body);
      calls.push(body);

      if (body.query.includes('query Teams')) {
        return jsonResponse({
          data: {
            teams: {
              nodes: [
                { id: 'team-uuid', key: 'TAB', name: 'Tablet Notes' }
              ]
            }
          }
        });
      }

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
    teamId: 'TAB',
    title: 'Support issue',
    description: 'Details',
    priority: 1
  });

  assert.equal(issue.identifier, 'TAB-123');
  assert.equal(calls.length, 2);
  assert.equal(calls[1].variables.input.teamId, 'team-uuid');
});

test('LinearClient passes UUID team ids without a lookup', async () => {
  const calls = [];
  const client = new LinearClient({
    apiKey: 'lin_api_key',
    fetchImpl: async (url, options) => {
      calls.push(JSON.parse(options.body));
      return jsonResponse({
        data: {
          issueCreate: {
            success: true,
            issue: {
              id: 'issue-id',
              identifier: 'TAB-124',
              title: 'Support issue',
              url: 'https://linear.app/tabletnotes/issue/TAB-124'
            }
          }
        }
      });
    }
  });

  await client.createIssue({
    teamId: '38abf509-9400-4268-a35d-cb64cc6db607',
    title: 'Support issue',
    description: 'Details',
    priority: 1
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].variables.input.teamId, '38abf509-9400-4268-a35d-cb64cc6db607');
});

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body)
  };
}

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { parseSupportInboxRoutes } = require('../supportInboxRouting');

const TAB_TEAM_ID = '38abf509-9400-4268-a35d-cb64cc6db607';
const LOO_TEAM_ID = '60112c28-9f70-4fc3-9e06-d5963b476947';
const GRANTED_AI_PROJECT_ID = 'fea7755f-3b05-4822-aaad-f298550d3a1c';

function parseEnvExampleInboxRoutes() {
  const envExample = fs.readFileSync(path.join(__dirname, '../../.env.example'), 'utf8');
  const match = envExample.match(/^SUPPORT_INBOX_ROUTES=(.*)$/m);
  assert.ok(match, 'SUPPORT_INBOX_ROUTES must be present in .env.example');
  return parseSupportInboxRoutes(match[1]);
}

test('parses independent Help Scout mailbox routes from production configuration', () => {
  const routes = parseSupportInboxRoutes(JSON.stringify({
    360464: {
      productName: 'Tablet Notes',
      mailboxName: 'TabletNotes-support',
      supportEmail: 'support@tabletnotes.io',
      identityAliases: ['TabletNotes'],
      agentGuidance: 'Prioritize lost recordings and App Store launch issues.',
      linearTeamId: TAB_TEAM_ID
    },
    371514: {
      productName: 'Granted AI',
      mailboxName: 'Granted AI Support',
      supportEmail: 'support@grantedai.app',
      supportSignature: 'Granted AI Support',
      agentGuidance: 'Use only details present in the ticket.',
      linearTeamId: LOO_TEAM_ID,
      linearProjectId: GRANTED_AI_PROJECT_ID,
      linearLabelIds: ['support-label']
    }
  }));

  assert.deepEqual(routes['360464'], {
    productName: 'Tablet Notes',
    mailboxName: 'TabletNotes-support',
    supportEmail: 'support@tabletnotes.io',
    identityAliases: ['TabletNotes'],
    supportSignature: 'Tablet Notes Support',
    agentGuidance: 'Prioritize lost recordings and App Store launch issues.',
    linearTeamId: TAB_TEAM_ID,
    linearLabelIds: []
  });
  assert.equal(routes['360464'].linearTeamId, TAB_TEAM_ID);
  assert.equal(routes['360464'].linearProjectId, undefined);
  assert.notEqual(routes['360464'].linearProjectId, GRANTED_AI_PROJECT_ID);
  assert.equal(routes['371514'].linearTeamId, LOO_TEAM_ID);
  assert.equal(routes['371514'].linearProjectId, GRANTED_AI_PROJECT_ID);
  assert.equal(routes['371514'].agentGuidance, 'Use only details present in the ticket.');
  assert.deepEqual(routes['371514'].linearLabelIds, ['support-label']);
});

test('committed .env.example routes mailbox 371514 to LOO and the Granted AI project', () => {
  const routes = parseEnvExampleInboxRoutes();

  assert.equal(routes['371514'].linearTeamId, LOO_TEAM_ID);
  assert.equal(routes['371514'].linearProjectId, GRANTED_AI_PROJECT_ID);
  assert.notEqual(routes['371514'].linearTeamId, TAB_TEAM_ID);
});

test('committed .env.example routes mailbox 360464 to TAB with no Granted AI project', () => {
  const routes = parseEnvExampleInboxRoutes();

  assert.equal(routes['360464'].linearTeamId, TAB_TEAM_ID);
  assert.equal(routes['360464'].linearProjectId, undefined);
  assert.notEqual(routes['360464'].linearTeamId, LOO_TEAM_ID);
  assert.notEqual(routes['360464'].linearProjectId, GRANTED_AI_PROJECT_ID);
});

test('rejects missing or invalid support inbox routing configuration', () => {
  assert.throws(
    () => parseSupportInboxRoutes(''),
    /SUPPORT_INBOX_ROUTES is required/
  );
  assert.throws(
    () => parseSupportInboxRoutes('{not-json'),
    /must be valid JSON/
  );
  assert.throws(
    () => parseSupportInboxRoutes(JSON.stringify({
      371514: {
        productName: 'Granted AI',
        mailboxName: 'Granted AI Support',
        supportEmail: 'support@grantedai.app',
        agentGuidance: 'Ticket-only support.'
      }
    })),
    /linearTeamId is required/
  );
});

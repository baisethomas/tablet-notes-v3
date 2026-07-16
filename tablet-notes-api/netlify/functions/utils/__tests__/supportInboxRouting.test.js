const test = require('node:test');
const assert = require('node:assert/strict');

const { parseSupportInboxRoutes } = require('../supportInboxRouting');

test('parses independent Help Scout mailbox routes from production configuration', () => {
  const routes = parseSupportInboxRoutes(JSON.stringify({
    360464: {
      productName: 'Tablet Notes',
      linearTeamId: '38abf509-9400-4268-a35d-cb64cc6db607'
    },
    371514: {
      productName: 'Granted AI',
      supportSignature: 'Granted AI Support',
      linearTeamId: 'ec3442ea-feb0-42a3-a355-bdb373c9bc0c',
      linearLabelIds: ['support-label']
    }
  }));

  assert.deepEqual(routes['360464'], {
    productName: 'Tablet Notes',
    supportSignature: 'Tablet Notes Support',
    linearTeamId: '38abf509-9400-4268-a35d-cb64cc6db607',
    linearLabelIds: []
  });
  assert.equal(routes['371514'].linearTeamId, 'ec3442ea-feb0-42a3-a355-bdb373c9bc0c');
  assert.deepEqual(routes['371514'].linearLabelIds, ['support-label']);
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
      371514: { productName: 'Granted AI' }
    })),
    /linearTeamId is required/
  );
});

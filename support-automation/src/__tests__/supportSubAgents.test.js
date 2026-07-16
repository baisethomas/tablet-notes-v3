const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildSubAgentReports,
  sanitizeDraftReplyWithReview
} = require('../supportSubAgents');

const crashContext = {
  productName: 'Tablet Notes',
  subject: 'App crashes after recording',
  customer: {
    firstName: 'Jordan',
    email: 'jordan@example.com'
  },
  latestCustomerMessage: 'I recorded a sermon and now the app crashes when I open the recording. iPadOS 18.5, Tablet Notes 1.0.2.',
  detectedMetadata: {
    appVersion: '1.0.2',
    osVersion: 'iPadOS 18.5'
  }
};

test('bug investigation sub-agent produces engineering handoff details', () => {
  const reports = buildSubAgentReports(crashContext, {
    category: 'bug',
    priority: 1,
    labels: ['support', 'bug', 'crash'],
    shouldCreateLinearIssue: true,
    shouldStartEngineeringWork: true
  });

  assert.equal(reports.engineering?.kind, 'bug_investigation');
  assert.equal(reports.engineering?.shouldStartEngineeringWork, true);
  assert.deepEqual(reports.engineering?.knownMetadata, [
    'appVersion: 1.0.2',
    'osVersion: iPadOS 18.5'
  ]);
  assert.ok(reports.engineering?.investigationSteps.some((step) => /crash logs/i.test(step)));
  assert.match(reports.linearAppendix, /Engineering Sub-Agent/);
  assert.match(reports.linearAppendix, /Look for crash logs/);
});

test('billing sub-agent avoids engineering handoff and asks for purchase context', () => {
  const reports = buildSubAgentReports({
    productName: 'Tablet Notes',
    subject: 'Restore purchase',
    latestCustomerMessage: 'I paid but cannot restore purchase.',
    detectedMetadata: {}
  }, {
    category: 'billing',
    priority: 2,
    labels: ['support', 'billing'],
    shouldCreateLinearIssue: false,
    shouldStartEngineeringWork: false
  });

  assert.equal(reports.billing?.kind, 'billing_support');
  assert.equal(reports.engineering, null);
  assert.match(reports.internalNoteAppendix, /Ask for a purchase or subscription screenshot/);
});

test('feature request sub-agent adds product discovery prompts', () => {
  const reports = buildSubAgentReports({
    productName: 'Tablet Notes',
    subject: 'Please add folders',
    latestCustomerMessage: 'I wish there was a way to organize sermons into folders.',
    detectedMetadata: {}
  }, {
    category: 'feature_request',
    priority: 4,
    labels: ['support', 'feature-request'],
    shouldCreateLinearIssue: true,
    shouldStartEngineeringWork: false
  });

  assert.equal(reports.product?.kind, 'feature_request_intake');
  assert.match(reports.linearAppendix, /Product Sub-Agent/);
  assert.match(reports.linearAppendix, /What workflow is blocked/);
});

test('reply safety sub-agent replaces another inbox identity', () => {
  const review = sanitizeDraftReplyWithReview(
    'Hi Jordan,\n\nThanks for contacting Tablet Notes.\n\nThanks,\nTablet Notes Support',
    {
      replacements: [
        { forbidden: 'Tablet Notes Support', replacement: 'Granted AI Support' },
        { forbidden: 'Tablet Notes', replacement: 'Granted AI' }
      ]
    }
  );

  assert.equal(review.changed, true);
  assert.doesNotMatch(review.draftReply, /Tablet Notes/);
  assert.match(review.draftReply, /Granted AI Support/);
  assert.match(review.reviewNotes.join('\n'), /another support inbox identity/);
});

test('reply safety sub-agent removes auto-send language and appends human review note', () => {
  const review = sanitizeDraftReplyWithReview(
    'Hi Jordan,\n\nI already fixed this and pushed a release. This was automatically sent.\n\nThanks,\nTablet Notes Support'
  );

  assert.equal(review.changed, true);
  assert.doesNotMatch(review.draftReply, /already fixed/i);
  assert.doesNotMatch(review.draftReply, /automatically sent/i);
  assert.match(review.reviewNotes.join('\n'), /Removed unsafe promise/);
});

test('engineering sub-agent requests metadata for the routed product', () => {
  const reports = buildSubAgentReports({
    productName: 'Granted AI',
    subject: 'Setup crashes',
    latestCustomerMessage: 'The app crashes during setup.',
    detectedMetadata: {}
  }, {
    category: 'bug',
    priority: 2,
    labels: ['support', 'bug'],
    shouldCreateLinearIssue: true,
    shouldStartEngineeringWork: true
  });

  assert.ok(reports.engineering.missingMetadata.includes('Granted AI app version'));
  assert.doesNotMatch(reports.linearAppendix, /Tablet Notes/);
});

const UNSAFE_REPLY_PATTERNS = [
  {
    pattern: /\b(already fixed|fixed this|pushed a release|shipped a fix|resolved this)\b/gi,
    replacement: 'I have shared this with our team for review',
    note: 'Removed unsafe promise that the issue was already fixed.'
  },
  {
    pattern: /\bautomatically sent\b/gi,
    replacement: 'drafted for review',
    note: 'Removed automation disclosure from customer-facing draft.'
  },
  {
    pattern: /\bguarantee(?:d)?\b/gi,
    replacement: 'expect',
    note: 'Removed guarantee language.'
  }
];

function buildSubAgentReports(context, triage) {
  const engineering = buildEngineeringReport(context, triage);
  const billing = triage.category === 'billing' ? buildBillingReport(context) : null;
  const product = triage.category === 'feature_request' ? buildProductReport(context) : null;

  return {
    engineering,
    billing,
    product,
    linearAppendix: buildLinearAppendix({ engineering, product }),
    internalNoteAppendix: buildInternalNoteAppendix({ engineering, billing, product })
  };
}

function sanitizeDraftReplyWithReview(draftReply, identity = {}) {
  let safeDraft = draftReply || '';
  const reviewNotes = [];

  for (const rule of UNSAFE_REPLY_PATTERNS) {
    if (rule.pattern.test(safeDraft)) {
      safeDraft = safeDraft.replace(rule.pattern, rule.replacement);
      reviewNotes.push(rule.note);
    }
    rule.pattern.lastIndex = 0;
  }

  const identityReview = sanitizeSupportIdentity(safeDraft, identity);
  safeDraft = identityReview.text;
  if (identityReview.changed) {
    reviewNotes.push('Replaced another support inbox identity with the routed product identity.');
  }

  return {
    draftReply: safeDraft.trim(),
    changed: reviewNotes.length > 0,
    reviewNotes
  };
}

function sanitizeSupportIdentity(value, identity = {}, options = {}) {
  let text = String(value || '');
  let changed = false;
  const replacements = (identity.replacements || [])
    .filter((item) => typeof item?.forbidden === 'string' && item.forbidden.trim() && typeof item?.replacement === 'string' && item.replacement.trim())
    .sort((a, b) => b.forbidden.length - a.forbidden.length);

  for (const item of replacements) {
    let replacement = item.replacement;
    if (options.labelMode) {
      replacement = replacement.toLowerCase().replace(/\s+/g, '-');
    }

    const pattern = buildIdentityPattern(item.forbidden);
    if (pattern.test(text)) {
      text = text.replace(pattern, replacement);
      changed = true;
    }
  }

  return { text, changed };
}

function buildEngineeringReport(context, triage) {
  if (!triage.shouldCreateLinearIssue || triage.category !== 'bug') {
    return null;
  }

  const knownMetadata = Object.entries(context.detectedMetadata || {})
    .map(([key, value]) => `${key}: ${value}`);
  const missingMetadata = [];
  const productName = context.productName;

  if (!context.detectedMetadata?.appVersion) {
    missingMetadata.push(`${productName} app version`);
  }

  if (!context.detectedMetadata?.osVersion) {
    missingMetadata.push('operating system or browser version');
  }

  return {
    kind: 'bug_investigation',
    shouldStartEngineeringWork: Boolean(triage.shouldStartEngineeringWork),
    knownMetadata,
    missingMetadata,
    investigationSteps: [
      'Look for crash logs or correlated errors around the conversation timestamp.',
      'Try to reproduce from the latest customer message using the detected app and OS version.',
      `Check recent ${productName} changes touching the affected flow.`,
      'Add or update a regression test before shipping a fix.'
    ],
    customerFollowUpQuestions: [
      'Which device and browser or app are you using?',
      'Does the issue happen every time or only in a specific workflow?',
      'What was the last successful step before the issue appeared?'
    ]
  };
}

function buildBillingReport() {
  return {
    kind: 'billing_support',
    checklist: [
      'Ask for a purchase or subscription screenshot if the current state is unclear.',
      'Ask which purchase channel and account the customer used.',
      'Check whether the customer is signed into the same account used for purchase.',
      'Escalate to engineering only if receipt verification or entitlement state appears wrong.'
    ]
  };
}

function buildProductReport() {
  return {
    kind: 'feature_request_intake',
    discoveryPrompts: [
      'What workflow is blocked without this feature?',
      'How often would the customer use it?',
      'What workaround are they using today?',
      'Which part of the product would this change affect?'
    ]
  };
}

function buildLinearAppendix({ engineering, product }) {
  const sections = [];

  if (engineering) {
    sections.push([
      '## Engineering Sub-Agent',
      '',
      `Start work: ${engineering.shouldStartEngineeringWork ? 'yes' : 'no'}`,
      '',
      'Known metadata:',
      formatList(engineering.knownMetadata.length ? engineering.knownMetadata : ['None detected']),
      '',
      'Missing metadata:',
      formatList(engineering.missingMetadata.length ? engineering.missingMetadata : ['None']),
      '',
      'Investigation steps:',
      formatList(engineering.investigationSteps),
      '',
      'Customer follow-up questions:',
      formatList(engineering.customerFollowUpQuestions)
    ].join('\n'));
  }

  if (product) {
    sections.push([
      '## Product Sub-Agent',
      '',
      'Discovery prompts:',
      formatList(product.discoveryPrompts)
    ].join('\n'));
  }

  return sections.join('\n\n');
}

function buildInternalNoteAppendix({ engineering, billing, product }) {
  const sections = [];

  if (engineering) {
    sections.push([
      'Engineering sub-agent:',
      `- Start work: ${engineering.shouldStartEngineeringWork ? 'yes' : 'no'}`,
      ...engineering.investigationSteps.map((step) => `- ${step}`)
    ].join('\n'));
  }

  if (billing) {
    sections.push([
      'Billing sub-agent:',
      ...billing.checklist.map((item) => `- ${item}`)
    ].join('\n'));
  }

  if (product) {
    sections.push([
      'Product sub-agent:',
      ...product.discoveryPrompts.map((prompt) => `- ${prompt}`)
    ].join('\n'));
  }

  return sections.join('\n\n');
}

function formatList(items) {
  return items.map((item) => `- ${item}`).join('\n');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildIdentityPattern(value) {
  const words = value.trim().split(/[\s_-]+/).map(escapeRegExp);
  return new RegExp(words.join('[\\s_-]+'), 'gi');
}

module.exports = {
  buildSubAgentReports,
  sanitizeDraftReplyWithReview,
  sanitizeSupportIdentity
};

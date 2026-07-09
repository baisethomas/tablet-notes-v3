const crypto = require('node:crypto');
const {
  buildSubAgentReports,
  sanitizeDraftReplyWithReview
} = require('./supportSubAgents');

const PROCESSABLE_EVENTS = new Set([
  'convo.created',
  'convo.customer.reply.created',
  'beacon.chat.created',
  'beacon.chat.customer.replied'
]);

function verifyHelpScoutSignature(rawBody, signature, secret) {
  if (!rawBody || !signature || !secret) {
    return false;
  }

  const expected = crypto.createHmac('sha1', secret).update(rawBody).digest('base64');
  const expectedBuffer = Buffer.from(expected);
  const actualBuffer = Buffer.from(String(signature).trim());

  if (expectedBuffer.length !== actualBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(expectedBuffer, actualBuffer);
}

function isProcessableHelpScoutEvent(eventName) {
  return PROCESSABLE_EVENTS.has(eventName);
}

function buildSupportContext(conversation) {
  if (!conversation || !conversation.id) {
    throw new Error('Help Scout conversation id is required');
  }

  const threads = getConversationThreads(conversation);
  const customerThreads = threads
    .filter(isCustomerThread)
    .sort((a, b) => new Date(a.createdAt || 0) - new Date(b.createdAt || 0));
  const latestCustomerThread = customerThreads[customerThreads.length - 1] || {};
  const latestCustomerMessage = cleanText(latestCustomerThread.body || latestCustomerThread.text || '');
  const allCustomerText = customerThreads
    .map((thread) => cleanText(thread.body || thread.text || ''))
    .filter(Boolean)
    .join('\n\n');
  const customer = normalizeCustomer(conversation.customer || latestCustomerThread.customer || {});

  return {
    conversationId: conversation.id,
    conversationNumber: conversation.number || null,
    subject: conversation.subject || 'No subject',
    status: conversation.status || null,
    createdAt: conversation.createdAt || null,
    mailbox: {
      id: conversation.mailbox?.id || null,
      name: conversation.mailbox?.name || null
    },
    customer,
    url: conversation._links?.web?.href || conversation.webUrl || null,
    latestCustomerMessage,
    allCustomerText,
    detectedMetadata: detectSupportMetadata(`${conversation.subject || ''}\n${allCustomerText}`)
  };
}

function triageSupportContext(context) {
  const text = `${context.subject}\n${context.allCustomerText || context.latestCustomerMessage}`.toLowerCase();

  if (containsAny(text, ['crash', 'crashes', 'crashed', 'freeze', 'frozen', 'won\'t open', 'does not open'])) {
    return buildTriage({
      category: 'bug',
      priority: 1,
      labels: ['support', 'bug', 'crash'],
      summary: 'Customer is reporting a crash or launch-blocking failure.',
      shouldCreateLinearIssue: true,
      shouldStartEngineeringWork: true
    });
  }

  if (containsAny(text, ['lost recording', 'lost audio', 'missing recording', 'deleted my recording', 'data loss', 'lost transcript', 'missing transcript'])) {
    return buildTriage({
      category: 'bug',
      priority: 1,
      labels: ['support', 'bug', 'data-loss'],
      summary: 'Customer is reporting possible data loss.',
      shouldCreateLinearIssue: true,
      shouldStartEngineeringWork: true
    });
  }

  if (containsAny(text, ['subscription', 'billing', 'charged', 'refund', 'purchase', 'restore purchase'])) {
    return buildTriage({
      category: 'billing',
      priority: 2,
      labels: ['support', 'billing'],
      summary: 'Customer needs billing or purchase support.',
      shouldCreateLinearIssue: false,
      shouldStartEngineeringWork: false
    });
  }

  if (containsAny(text, ['feature request', 'would love', 'can you add', 'please add', 'wish there was'])) {
    return buildTriage({
      category: 'feature_request',
      priority: 4,
      labels: ['support', 'feature-request'],
      summary: 'Customer is asking for a product enhancement.',
      shouldCreateLinearIssue: true,
      shouldStartEngineeringWork: false
    });
  }

  if (containsAny(text, ['how do i', 'how can i', 'where do i', 'what is the best way', 'can i export', 'export'])) {
    return buildTriage({
      category: 'how_to',
      priority: 4,
      labels: ['support', 'question'],
      summary: 'Customer has a how-to question.',
      shouldCreateLinearIssue: false,
      shouldStartEngineeringWork: false
    });
  }

  return buildTriage({
    category: 'needs_review',
    priority: 3,
    labels: ['support', 'needs-triage'],
    summary: 'Customer request needs human review before routing.',
    shouldCreateLinearIssue: false,
    shouldStartEngineeringWork: false
  });
}

function buildLinearIssueInput(context, triage, config) {
  if (!config?.teamId) {
    throw new Error('Linear team id is required');
  }

  const subAgentReports = config.subAgentReports || buildSubAgentReports(context, triage);
  const input = {
    teamId: config.teamId,
    title: `[Support] ${context.subject}`,
    description: buildLinearIssueDescription(context, triage, subAgentReports),
    priority: triage.priority
  };

  if (config.projectId) {
    input.projectId = config.projectId;
  }

  if (config.assigneeId) {
    input.assigneeId = config.assigneeId;
  }

  if (Array.isArray(config.labelIds) && config.labelIds.length > 0) {
    input.labelIds = config.labelIds;
  }

  return input;
}

function buildHelpScoutDraftReply(context, triage) {
  const firstName = context.customer.firstName || 'there';

  if (triage.category === 'bug') {
    return [
      `Hi ${firstName},`,
      '',
      "I'm sorry Tablet Notes is giving you trouble here. We're looking into this and I have opened it with engineering so we can investigate it properly.",
      '',
      'If you have a minute, please send any extra details you have about the device, iOS/iPadOS version, Tablet Notes version, and what happened right before the issue appeared.',
      '',
      'Thanks,',
      'Tablet Notes Support'
    ].join('\n');
  }

  if (triage.category === 'billing') {
    return [
      `Hi ${firstName},`,
      '',
      'Thanks for reaching out. I can help with this purchase question. Please send the email used for the App Store purchase and a screenshot of the subscription state shown in Tablet Notes if you have it handy.',
      '',
      'Thanks,',
      'Tablet Notes Support'
    ].join('\n');
  }

  if (triage.category === 'feature_request') {
    return [
      `Hi ${firstName},`,
      '',
      'Thanks for the suggestion. I have captured this for product review so we can weigh it with the rest of the Tablet Notes roadmap.',
      '',
      'Thanks,',
      'Tablet Notes Support'
    ].join('\n');
  }

  return [
    `Hi ${firstName},`,
    '',
    'Thanks for reaching out. I am taking a look and will follow up with the best next step.',
    '',
    'Thanks,',
    'Tablet Notes Support'
  ].join('\n');
}

async function runSupportWorkflow({ eventName, payload, helpScoutClient, linearClient, supportAgent, config = {} }) {
  if (!isProcessableHelpScoutEvent(eventName)) {
    return {
      processed: false,
      reason: `Ignored Help Scout event: ${eventName || 'unknown'}`
    };
  }

  const conversationId = getConversationId(payload);
  if (!conversationId) {
    throw new Error('Help Scout webhook payload did not include a conversation id');
  }

  const conversation = await helpScoutClient.getConversation(conversationId);
  const context = buildSupportContext(conversation);
  const fallbackTriage = triageSupportContext(context);
  let triage = fallbackTriage;
  let draftReply = buildHelpScoutDraftReply(context, triage);
  let agentError = null;

  if (supportAgent?.analyze) {
    try {
      const agentDecision = await supportAgent.analyze(context, fallbackTriage);
      triage = agentDecision.triage || fallbackTriage;
      draftReply = agentDecision.draftReply || draftReply;
    } catch (error) {
      agentError = error.message;
    }
  }

  const subAgentReports = buildSubAgentReports(context, triage);
  const replyReview = sanitizeDraftReplyWithReview(draftReply);
  draftReply = replyReview.draftReply;

  let linearIssue = null;
  if (triage.shouldCreateLinearIssue) {
    linearIssue = await linearClient.createIssue(buildLinearIssueInput(context, triage, {
      teamId: config.linearTeamId,
      projectId: config.linearProjectId,
      assigneeId: config.linearAssigneeId,
      labelIds: config.linearLabelIds,
      subAgentReports
    }));
  }

  const helpScoutDraftReply = await helpScoutClient.createDraftReply(context.conversationId, {
    customer: { id: context.customer.id },
    text: draftReply,
    draft: true
  });

  await helpScoutClient.createNote(context.conversationId, {
    text: buildInternalNote(context, triage, linearIssue, {
      subAgentReports,
      replyReview
    })
  });

  return {
    processed: true,
    context,
    triage,
    linearIssue,
    helpScoutDraftReply,
    draftReply,
    agentError,
    subAgentReports,
    replyReview
  };
}

function buildTriage({ category, priority, labels, summary, shouldCreateLinearIssue, shouldStartEngineeringWork }) {
  return {
    category,
    priority,
    labels,
    summary,
    shouldCreateLinearIssue,
    shouldStartEngineeringWork
  };
}

function buildLinearIssueDescription(context, triage, subAgentReports = buildSubAgentReports(context, triage)) {
  const metadata = Object.entries(context.detectedMetadata)
    .map(([key, value]) => `- ${key}: ${value}`)
    .join('\n') || '- None detected';

  const sections = [
    `## Support Summary`,
    '',
    triage.summary,
    '',
    `## Customer`,
    '',
    `Customer: ${formatCustomer(context.customer)}`,
    `Help Scout: ${context.url || `Conversation ${context.conversationId}`}`,
    `Conversation #: ${context.conversationNumber || 'unknown'}`,
    '',
    `## Latest Customer Message`,
    '',
    context.latestCustomerMessage || '_No customer message found._',
    '',
    `## Detected Metadata`,
    '',
    metadata,
    '',
    `## Agent Triage`,
    '',
    `Category: ${triage.category}`,
    `Priority: ${triage.priority}`,
    `Labels: ${triage.labels.join(', ')}`,
    `Start engineering work: ${triage.shouldStartEngineeringWork ? 'yes' : 'no'}`
  ];

  if (subAgentReports.linearAppendix) {
    sections.push('', subAgentReports.linearAppendix);
  }

  return sections.join('\n');
}

function buildInternalNote(context, triage, linearIssue, options = {}) {
  const note = [
    'Support automation triage',
    '',
    `Category: ${triage.category}`,
    `Priority: ${triage.priority}`,
    `Summary: ${triage.summary}`,
    `Engineering work: ${triage.shouldStartEngineeringWork ? 'recommended' : 'not recommended'}`,
    linearIssue ? `Linear: ${linearIssue.url || linearIssue.identifier || linearIssue.id}` : 'Linear: not created',
    '',
    'A draft reply was created for human review.'
  ];

  if (options.subAgentReports?.internalNoteAppendix) {
    note.push('', options.subAgentReports.internalNoteAppendix);
  }

  if (options.replyReview?.changed) {
    note.push('', 'Reply safety sub-agent:', ...options.replyReview.reviewNotes.map((item) => `- ${item}`));
  }

  return note.join('\n');
}

function getConversationId(payload) {
  return payload?.id || payload?.conversation?.id || payload?.conversationId || null;
}

function getConversationThreads(conversation) {
  if (Array.isArray(conversation._embedded?.threads)) {
    return conversation._embedded.threads;
  }

  if (Array.isArray(conversation.threads)) {
    return conversation.threads;
  }

  return [];
}

function isCustomerThread(thread) {
  return thread?.type === 'customer' ||
    thread?.type === 'chat' ||
    thread?.createdBy?.type === 'customer';
}

function cleanText(value) {
  return String(value || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function normalizeCustomer(customer) {
  const emails = customer.emails || [];
  const primaryEmail = customer.email || emails[0]?.value || emails[0] || null;

  return {
    id: customer.id || null,
    firstName: customer.firstName || customer.first_name || '',
    lastName: customer.lastName || customer.last_name || '',
    email: primaryEmail
  };
}

function formatCustomer(customer) {
  const name = [customer.firstName, customer.lastName].filter(Boolean).join(' ') || 'Unknown customer';
  return customer.email ? `${name} <${customer.email}>` : name;
}

function detectSupportMetadata(text) {
  const metadata = {};
  const appVersion = text.match(/(?:Tablet Notes\s+|version\s+|v)(\d+(?:\.\d+){1,3})/i);
  const osVersion = text.match(/\b(iPadOS|iOS)\s*(\d+(?:\.\d+){0,2})/i);

  if (appVersion) {
    metadata.appVersion = appVersion[1];
  }

  if (osVersion) {
    metadata.osVersion = `${normalizeOsName(osVersion[1])} ${osVersion[2]}`;
  }

  return metadata;
}

function normalizeOsName(name) {
  return name.toLowerCase() === 'ipados' ? 'iPadOS' : 'iOS';
}

function containsAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

module.exports = {
  buildHelpScoutDraftReply,
  buildInternalNote,
  buildLinearIssueInput,
  buildSupportContext,
  isProcessableHelpScoutEvent,
  runSupportWorkflow,
  triageSupportContext,
  verifyHelpScoutSignature
};

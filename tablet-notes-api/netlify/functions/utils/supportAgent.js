const OpenAI = require('openai');
const { buildHelpScoutDraftReply } = require('./supportAutomation');

const VALID_CATEGORIES = new Set([
  'bug',
  'billing',
  'feature_request',
  'how_to',
  'needs_review',
  'account',
  'app_store_review'
]);

class SupportAgent {
  constructor({
    apiKey = process.env.OPENAI_API_KEY,
    model = process.env.SUPPORT_AGENT_MODEL || 'gpt-4o-mini',
    openAIClient = null
  } = {}) {
    if (!openAIClient && !apiKey) {
      throw new Error('OpenAI API key is required for SupportAgent');
    }

    this.model = model;
    this.openAIClient = openAIClient || new OpenAI({ apiKey });
  }

  async analyze(context, fallbackTriage) {
    const response = await this.openAIClient.chat.completions.create({
      model: this.model,
      messages: [
        {
          role: 'system',
          content: [
            'You are the Tablet Notes support triage agent.',
            'Return only JSON. Do not send customer replies directly.',
            'Keep replies as drafts for human review.',
            'Prioritize crashes, data loss, lost recordings, account lockouts, and App Store launch issues.',
            'Use priority 1 urgent, 2 high, 3 medium, 4 low.',
            'Create Linear issues for product bugs and feature requests. Do not create Linear issues for ordinary how-to or billing requests unless engineering is needed.'
          ].join('\n')
        },
        {
          role: 'user',
          content: JSON.stringify({
            expectedJsonShape: {
              category: 'bug | billing | feature_request | how_to | needs_review | account | app_store_review',
              priority: '1 | 2 | 3 | 4',
              labels: ['support', 'bug'],
              summary: 'one sentence internal summary',
              shouldCreateLinearIssue: true,
              shouldStartEngineeringWork: true,
              draftReply: 'customer-facing draft reply signed Tablet Notes Support'
            },
            fallbackTriage,
            ticket: context
          })
        }
      ],
      temperature: 0.2,
      max_tokens: 900,
      response_format: { type: 'json_object' }
    });

    const content = response.choices?.[0]?.message?.content || '{}';
    return normalizeAgentDecision(JSON.parse(content), fallbackTriage, context);
  }
}

function normalizeAgentDecision(rawDecision, fallbackTriage, context) {
  const fallbackDraft = buildHelpScoutDraftReply(context, fallbackTriage);

  if (!rawDecision || typeof rawDecision !== 'object') {
    return {
      triage: fallbackTriage,
      draftReply: fallbackDraft
    };
  }

  if (!VALID_CATEGORIES.has(rawDecision.category)) {
    return {
      triage: fallbackTriage,
      draftReply: fallbackDraft
    };
  }

  const category = rawDecision.category;
  const priority = normalizePriority(rawDecision.priority, fallbackTriage.priority);
  const labels = normalizeLabels(rawDecision.labels, fallbackTriage.labels);
  const summary = normalizeSummary(rawDecision.summary, fallbackTriage.summary);
  const shouldCreateLinearIssue = typeof rawDecision.shouldCreateLinearIssue === 'boolean'
    ? rawDecision.shouldCreateLinearIssue
    : fallbackTriage.shouldCreateLinearIssue;
  const shouldStartEngineeringWork = typeof rawDecision.shouldStartEngineeringWork === 'boolean'
    ? rawDecision.shouldStartEngineeringWork
    : fallbackTriage.shouldStartEngineeringWork;
  const draftReply = normalizeDraftReply(rawDecision.draftReply, fallbackDraft);

  return {
    triage: {
      category,
      priority,
      labels,
      summary,
      shouldCreateLinearIssue,
      shouldStartEngineeringWork
    },
    draftReply
  };
}

function normalizePriority(priority, fallbackPriority) {
  const numericPriority = Number(priority);
  if (!Number.isInteger(numericPriority)) {
    return fallbackPriority;
  }

  return Math.min(4, Math.max(1, numericPriority));
}

function normalizeLabels(labels, fallbackLabels) {
  if (!Array.isArray(labels)) {
    return fallbackLabels;
  }

  const normalized = labels
    .filter((label) => typeof label === 'string')
    .map((label) => label.trim().toLowerCase())
    .filter(Boolean)
    .slice(0, 8);

  return normalized.length > 0 ? Array.from(new Set(normalized)) : fallbackLabels;
}

function normalizeSummary(summary, fallbackSummary) {
  if (typeof summary !== 'string' || !summary.trim()) {
    return fallbackSummary;
  }

  return summary.trim().slice(0, 500);
}

function normalizeDraftReply(draftReply, fallbackDraft) {
  if (typeof draftReply !== 'string' || draftReply.trim().length < 20) {
    return fallbackDraft;
  }

  return draftReply.trim().slice(0, 3000);
}

module.exports = {
  SupportAgent,
  normalizeAgentDecision
};

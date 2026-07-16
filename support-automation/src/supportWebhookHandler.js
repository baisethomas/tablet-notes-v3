const { HelpScoutClient } = require('./helpScoutClient');
const { LinearClient } = require('./linearClient');
const { SupportAgent } = require('./supportAgent');
const { parseSupportInboxRoutes } = require('./supportInboxRouting');
const {
  isProcessableHelpScoutEvent,
  runSupportWorkflow,
  verifyHelpScoutSignature
} = require('./supportAutomation');
const { recordAgentRun } = require('./agentRunRecorder');

const RESPONSE_HEADERS = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY'
};

async function handleSupportWebhook(request, options = {}) {
  const env = options.env || process.env;
  const logger = options.logger || createLogger();

  if (request.method === 'OPTIONS') {
    return response(204, null, {
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-HelpScout-Event, X-HelpScout-Signature'
    });
  }

  if (request.method !== 'POST') {
    return response(405, { error: 'Method Not Allowed' });
  }

  const webhookSecret = env.HELPSCOUT_WEBHOOK_SECRET;
  if (!webhookSecret) {
    logger.error('Support webhook secret is not configured');
    return response(500, { error: 'Support webhook is not configured' });
  }

  const signature = getHeader(request.headers, 'x-helpscout-signature');
  if (!verifyHelpScoutSignature(request.rawBody || '', signature, webhookSecret)) {
    logger.warn('Help Scout webhook signature failed');
    return response(401, { error: 'Invalid Help Scout signature' });
  }

  let payload;
  try {
    payload = JSON.parse(request.rawBody || '{}');
  } catch (error) {
    return response(400, { error: 'Invalid JSON payload' });
  }

  const eventName = getHeader(request.headers, 'x-helpscout-event');
  if (!isProcessableHelpScoutEvent(eventName)) {
    return response(202, {
      processed: false,
      reason: `Ignored Help Scout event: ${eventName || 'unknown'}`
    });
  }

  const supportAgent = env.OPENAI_API_KEY
    ? new SupportAgent({ apiKey: env.OPENAI_API_KEY, model: env.SUPPORT_AGENT_MODEL })
    : null;
  const startedAt = Date.now();

  try {
    const result = await runSupportWorkflow({
      eventName,
      payload,
      helpScoutClient: options.helpScoutClient || new HelpScoutClient({
        appId: env.HELPSCOUT_APP_ID,
        appSecret: env.HELPSCOUT_APP_SECRET
      }),
      linearClient: options.linearClient || {
        createIssue: async (input) => {
          const client = new LinearClient({
            apiKey: env.LINEAR_API_KEY,
            authHeader: env.LINEAR_AUTH_HEADER_VALUE
          });
          return client.createIssue(input);
        }
      },
      supportAgent: options.supportAgent === undefined ? supportAgent : options.supportAgent,
      config: {
        inboxRoutes: parseSupportInboxRoutes(env.SUPPORT_INBOX_ROUTES)
      }
    });

    if (result.processed) {
      await (options.recordAgentRun || recordAgentRun)({
        result,
        startedAt,
        durationMs: Date.now() - startedAt,
        llmEnabled: Boolean(supportAgent),
        logger,
        env
      });
    }

    logger.info('Support workflow completed', {
      processed: result.processed,
      product: result.route?.productName,
      category: result.triage?.category
    });

    return response(202, {
      processed: result.processed,
      reason: result.reason,
      category: result.triage?.category,
      product: result.route?.productName || null,
      helpScoutMailbox: result.context?.mailbox?.id || null,
      linearIssue: result.linearIssue?.identifier || result.linearIssue?.id || null,
      helpScoutDraftReply: result.helpScoutDraftReply?.id || null
    });
  } catch (error) {
    await (options.recordAgentRun || recordAgentRun)({
      error,
      startedAt,
      durationMs: Date.now() - startedAt,
      llmEnabled: Boolean(supportAgent),
      logger,
      env
    });
    logger.error('Support workflow failed', { error: error.message });
    return response(500, { error: 'Support workflow failed' });
  }
}

function getHeader(headers = {}, name) {
  if (typeof headers.get === 'function') {
    return headers.get(name);
  }

  const match = Object.keys(headers).find((key) => key.toLowerCase() === name.toLowerCase());
  const value = match ? headers[match] : null;
  return Array.isArray(value) ? value[0] : value;
}

function response(statusCode, body, headers = {}) {
  return {
    statusCode,
    headers: { ...RESPONSE_HEADERS, ...headers },
    body: body === null ? '' : JSON.stringify(body)
  };
}

function createLogger() {
  return {
    info: (message, meta = {}) => console.log(JSON.stringify({ level: 'INFO', message, ...meta })),
    warn: (message, meta = {}) => console.warn(JSON.stringify({ level: 'WARN', message, ...meta })),
    error: (message, meta = {}) => console.error(JSON.stringify({ level: 'ERROR', message, ...meta }))
  };
}

module.exports = {
  handleSupportWebhook
};

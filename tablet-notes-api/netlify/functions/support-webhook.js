const {
  createErrorResponse,
  createSuccessResponse,
  handleCORS
} = require('./utils/security');
const { HelpScoutClient } = require('./utils/helpScoutClient');
const { LinearClient } = require('./utils/linearClient');
const { SupportAgent } = require('./utils/supportAgent');
const {
  isProcessableHelpScoutEvent,
  runSupportWorkflow,
  verifyHelpScoutSignature
} = require('./utils/supportAutomation');
const { recordAgentRun } = require('./utils/agentRunRecorder');
const { withLogging } = require('./utils/logger');

exports.handler = withLogging('support-webhook', async (event) => {
  const logger = event.logger;

  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  const webhookSecret = process.env.HELPSCOUT_WEBHOOK_SECRET;
  if (!webhookSecret) {
    logger.error('Support webhook secret is not configured');
    return createErrorResponse(new Error('Support webhook is not configured'), 500);
  }

  const signature = event.headers['x-helpscout-signature'] || event.headers['X-HelpScout-Signature'];
  if (!verifyHelpScoutSignature(event.body || '', signature, webhookSecret)) {
    logger.security('helpscout_webhook_signature_failed', {
      hasSignature: Boolean(signature)
    });
    return createErrorResponse(new Error('Invalid Help Scout signature'), 401);
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch (error) {
    return createErrorResponse(new Error('Invalid JSON payload'), 400);
  }

  try {
    const eventName = event.headers['x-helpscout-event'] || event.headers['X-HelpScout-Event'];
    if (!isProcessableHelpScoutEvent(eventName)) {
      return createSuccessResponse({
        processed: false,
        reason: `Ignored Help Scout event: ${eventName || 'unknown'}`
      }, 202);
    }

    const helpScoutClient = new HelpScoutClient({
      appId: process.env.HELPSCOUT_APP_ID,
      appSecret: process.env.HELPSCOUT_APP_SECRET
    });
    const linearClient = {
      createIssue: async (input) => {
        const client = new LinearClient({
          apiKey: process.env.LINEAR_API_KEY,
          authHeader: process.env.LINEAR_AUTH_HEADER_VALUE
        });
        return client.createIssue(input);
      }
    };
    const supportAgent = process.env.OPENAI_API_KEY
      ? new SupportAgent({ apiKey: process.env.OPENAI_API_KEY })
      : null;

    const startedAt = Date.now();
    let result;
    try {
      result = await runSupportWorkflow({
        eventName,
        payload,
        helpScoutClient,
        linearClient,
        supportAgent,
        config: {
          linearTeamId: process.env.LINEAR_TEAM_ID,
          linearProjectId: process.env.LINEAR_PROJECT_ID,
          linearAssigneeId: process.env.LINEAR_ASSIGNEE_ID,
          linearLabelIds: parseCsv(process.env.LINEAR_LABEL_IDS)
        }
      });
    } catch (workflowError) {
      // Record the failed run in the brain, then rethrow to the outer handler.
      await recordAgentRun({
        error: workflowError,
        startedAt,
        durationMs: Date.now() - startedAt,
        llmEnabled: Boolean(supportAgent),
        logger
      });
      throw workflowError;
    }

    if (result.processed) {
      await recordAgentRun({
        result,
        startedAt,
        durationMs: Date.now() - startedAt,
        llmEnabled: Boolean(supportAgent),
        logger
      });
    }

    logger.info('Support workflow completed', {
      processed: result.processed,
      category: result.triage?.category,
      createdLinearIssue: Boolean(result.linearIssue)
    });

    return createSuccessResponse({
      processed: result.processed,
      reason: result.reason,
      category: result.triage?.category,
      linearIssue: result.linearIssue?.identifier || result.linearIssue?.id || null,
      helpScoutDraftReply: result.helpScoutDraftReply?.id || null
    }, 202);
  } catch (error) {
    logger.error('Support workflow failed', {
      error: error.message
    }, error);
    return createErrorResponse(error, 500);
  }
});

function parseCsv(value) {
  if (!value) {
    return [];
  }

  return value.split(',').map((item) => item.trim()).filter(Boolean);
}

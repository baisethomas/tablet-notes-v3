/**
 * Agent run recorder — writes one row per support-agent run to the
 * "Agent Runs" database in the Loom & Logic Labs Notion HQ (the second brain).
 *
 * Fire-and-forget by design: recording failures are logged and swallowed so
 * they can never break the customer-facing support workflow.
 *
 * Env: NOTION_API_KEY (internal integration token, shared with the HQ page),
 *      NOTION_AGENT_RUNS_DB_ID (database id of the "Agent Runs" database).
 */

const NOTION_API = 'https://api.notion.com/v1';
const NOTION_VERSION = '2022-06-28';
const RECORD_TIMEOUT_MS = 5000;

const PRIORITY_NAMES = { 1: 'Urgent', 2: 'High', 3: 'Medium', 4: 'Low' };

/**
 * Derive a compact stage map from the workflow result.
 * Format: "fetch:ok|triage:ok|llm:ok|subagents:ok|sanitize:flag|linear:skip|draft:ok|note:ok"
 * States: ok | flag (sanitizer rewrote the draft) | skip | fail
 */
function deriveStages(result, { llmEnabled, error } = {}) {
  if (error) {
    // Workflow threw — mark what we know succeeded, fail the rest generically.
    const gotContext = Boolean(result?.context);
    return [
      `fetch:${gotContext ? 'ok' : 'fail'}`,
      'triage:fail',
      'llm:fail',
      'subagents:fail',
      'sanitize:fail',
      'linear:fail',
      'draft:fail',
      'note:fail'
    ].join('|');
  }

  const stages = [
    'fetch:ok',
    'triage:ok',
    `llm:${!llmEnabled ? 'skip' : result.agentError ? 'fail' : 'ok'}`,
    `subagents:${result.subAgentReports ? 'ok' : 'skip'}`,
    `sanitize:${result.replyReview?.changed ? 'flag' : 'ok'}`,
    `linear:${result.linearIssue ? 'ok' : 'skip'}`,
    `draft:${result.helpScoutDraftReply ? 'ok' : 'skip'}`,
    'note:ok'
  ];

  return stages.join('|');
}

function buildRunProperties({ result, error, startedAt, durationMs, llmEnabled }) {
  const context = result?.context || {};
  const triage = result?.triage || {};

  const number = context.conversationNumber ? `#${context.conversationNumber} ` : '';
  const subject = context.subject || 'Unknown conversation';
  const title = error
    ? `${number}${subject} — FAILED`
    : `${number}${subject}`;

  const properties = {
    Run: { title: [{ text: { content: title.slice(0, 200) } }] },
    Agent: { select: { name: 'Tablet Support' } },
    Status: { select: { name: error ? 'Failed' : 'Processed' } },
    Started: { date: { start: new Date(startedAt).toISOString() } },
    'Duration (ms)': { number: Math.round(durationMs) },
    Stages: {
      rich_text: [{ text: { content: deriveStages(result, { llmEnabled, error }) } }]
    }
  };

  if (triage.category) {
    properties.Category = { select: { name: triage.category } };
  }

  if (PRIORITY_NAMES[triage.priority]) {
    properties.Priority = { select: { name: PRIORITY_NAMES[triage.priority] } };
  }

  if (context.url) {
    properties.Conversation = { url: context.url };
  }

  if (result?.linearIssue?.url) {
    properties['Linear Issue'] = { url: result.linearIssue.url };
  }

  const errorText = error?.message || result?.agentError;
  if (errorText) {
    properties.Error = { rich_text: [{ text: { content: String(errorText).slice(0, 1900) } }] };
  }

  return properties;
}

function buildRunPageContent({ result }) {
  if (!result?.triage) return [];

  const lines = [
    `Summary: ${result.triage.summary || '(none)'}`,
    `Labels: ${(result.triage.labels || []).join(', ') || '(none)'}`,
    `Create Linear issue: ${result.triage.shouldCreateLinearIssue ? 'yes' : 'no'}`,
    `Start engineering work: ${result.triage.shouldStartEngineeringWork ? 'yes' : 'no'}`
  ];

  if (result.replyReview?.reviewNotes?.length) {
    lines.push(`Sanitizer notes: ${result.replyReview.reviewNotes.join(' · ')}`);
  }

  return [
    {
      object: 'block',
      type: 'paragraph',
      paragraph: {
        rich_text: [{ text: { content: lines.join('\n').slice(0, 1900) } }]
      }
    }
  ];
}

/**
 * Record a run. Never throws — failures are reported through the logger only.
 */
async function recordAgentRun({ result, error, startedAt, durationMs, llmEnabled, logger }) {
  const apiKey = process.env.NOTION_API_KEY;
  const databaseId = process.env.NOTION_AGENT_RUNS_DB_ID;

  if (!apiKey || !databaseId) {
    logger?.warn?.('Agent run not recorded: NOTION_API_KEY or NOTION_AGENT_RUNS_DB_ID missing');
    return { recorded: false, reason: 'not_configured' };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RECORD_TIMEOUT_MS);

  try {
    const response = await fetch(`${NOTION_API}/pages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Notion-Version': NOTION_VERSION,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        parent: { database_id: databaseId },
        properties: buildRunProperties({ result, error, startedAt, durationMs, llmEnabled }),
        children: buildRunPageContent({ result })
      }),
      signal: controller.signal
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      logger?.warn?.('Agent run recording failed', {
        status: response.status,
        body: body.slice(0, 300)
      });
      return { recorded: false, reason: `notion_${response.status}` };
    }

    return { recorded: true };
  } catch (err) {
    logger?.warn?.('Agent run recording failed', { error: err.message });
    return { recorded: false, reason: err.name === 'AbortError' ? 'timeout' : err.message };
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = {
  recordAgentRun,
  deriveStages,
  buildRunProperties
};

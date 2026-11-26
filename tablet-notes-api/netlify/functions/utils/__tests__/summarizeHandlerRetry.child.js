'use strict';

// Isolated process: stubs openai / supabase before loading summarize.js so
// the sibling utils tests (which require the real @supabase/supabase-js) are
// not poisoned via require.cache.

const Module = require('module');
const originalLoad = Module._load;

const NARRATIVE = `TITLE: A Message of Hope

This sermon was a warm conversation about trusting God when life is hard.
The speaker told stories and encouraged the congregation to keep going.
There was no list of passages and no section headings at all.
`;

const SECTIONED = `TITLE: Hope That Holds

**Main Scripture Text**
Romans 8:28

**Brief Summary**
The speaker taught that hope is disciplined remembrance of God's faithfulness.

**Key Points**
- Trust God's hands before the story makes sense.

**Memorable Elements**
Hope is not denial. Hope is disciplined remembrance.

**Scripture References**
- Romans 8:28
`;

const openaiCalls = [];

function MockOpenAI() {
  return {
    chat: {
      completions: {
        create: async ({ messages }) => {
          openaiCalls.push(messages);
          const content = openaiCalls.length === 1 ? NARRATIVE : SECTIONED;
          return {
            choices: [{ message: { content } }],
            usage: { total_tokens: openaiCalls.length === 1 ? 10 : 20 }
          };
        }
      }
    }
  };
}

const mockSupabase = {
  createClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          single: async () => ({
            data: {
              subscription_tier: 'free',
              subscription_status: 'free',
              subscription_expiry: null
            },
            error: null
          })
        })
      })
    })
  })
};

Module._load = function (request, parent, isMain) {
  if (request === 'openai') return MockOpenAI;
  if (request === '@supabase/supabase-js') return mockSupabase;
  return originalLoad.apply(this, arguments);
};

process.env.OPENAI_API_KEY = process.env.OPENAI_API_KEY || 'test-openai-key';
process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://example.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'test-service-role';
process.env.ASSEMBLYAI_WEBHOOK_SECRET = process.env.ASSEMBLYAI_WEBHOOK_SECRET || 'test-internal-secret';
process.env.LOG_LEVEL = process.env.LOG_LEVEL || 'ERROR';

const { handler } = require('../../summarize');
const { buildRetryUserMessage, missingRequiredHeadings } = require('../summaryFormat');

const USER_ID = '11111111-1111-4111-8111-111111111111';
const transcript = 'The pastor taught from Romans 8:28 that God works all things for good for those who love him. '.repeat(2);

(async () => {
  const response = await handler(
    {
      httpMethod: 'POST',
      headers: {
        'x-tabletnotes-internal-secret': process.env.ASSEMBLYAI_WEBHOOK_SECRET,
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        userId: USER_ID,
        text: transcript,
        serviceType: 'Sermon',
        length: 'medium',
        tone: 'conversational'
      })
    },
    {}
  );

  const body = JSON.parse(response.body || '{}');
  const retryUser = buildRetryUserMessage(missingRequiredHeadings(NARRATIVE));
  const secondMessages = openaiCalls[1] || [];
  const assistant = secondMessages.find((m) => m.role === 'assistant');
  const lastUser = [...secondMessages].reverse().find((m) => m.role === 'user');

  const report = {
    statusCode: response.statusCode,
    callCount: openaiCalls.length,
    success: body.success === true,
    summary: body.data && body.data.summary,
    title: body.data && body.data.title,
    secondHasAssistantFirstContent: Boolean(assistant && assistant.content === NARRATIVE),
    secondHasRetryUserMessage: Boolean(lastUser && lastUser.content === retryUser),
    returnedSectionedSummary: Boolean(body.data && String(body.data.summary).includes('**Brief Summary**'))
  };

  process.stdout.write(`${JSON.stringify(report)}\n`);
  const ok =
    report.statusCode === 200 &&
    report.callCount === 2 &&
    report.success &&
    report.secondHasAssistantFirstContent &&
    report.secondHasRetryUserMessage &&
    report.returnedSectionedSummary;
  process.exit(ok ? 0 : 1);
})().catch((err) => {
  process.stderr.write(`${err && err.stack ? err.stack : err}\n`);
  process.exit(1);
});

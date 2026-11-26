const test = require('node:test');
const assert = require('node:assert/strict');

const {
  REQUIRED_HEADINGS,
  missingRequiredHeadings,
  hasRequiredHeadings,
  completeWithHeadingRetry,
  buildRetryUserMessage,
  MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION
} = require('../summaryFormat');
const { buildSummarizeSystemPrompt } = require('../summarizePrompt');

// TAB-120: gpt-4o-mini at temperature 0.7 often returns narrative prose and
// drops Scripture References. Option 2 (smallest that can meet 20/20): the
// response contract always includes the required headings, validation checks
// them, and a miss retries once.

const SECTIONED_BASIC = `TITLE: Hope That Holds

**Main Scripture Text**
Romans 8:28

**Brief Summary**
The speaker taught that hope is disciplined remembrance of God's faithfulness.

**Key Points**
- Trust God's hands before the story makes sense.
- Remembrance carries courage into the next step.

**Memorable Elements**
Hope is not denial. Hope is disciplined remembrance.

**Scripture References**
- Romans 8:28
- Philippians 4:13
`;

const NARRATIVE = `TITLE: A Message of Hope

This sermon was a warm conversation about trusting God when life is hard.
The speaker told stories and encouraged the congregation to keep going.
There was no list of passages and no section headings at all.
`;

test('REQUIRED_HEADINGS names the five basic-tier sections the prompt always asks for', () => {
  assert.deepEqual(REQUIRED_HEADINGS, [
    'Main Scripture Text',
    'Brief Summary',
    'Key Points',
    'Memorable Elements',
    'Scripture References'
  ]);
});

test('a sectioned basic-tier summary has no missing headings', () => {
  assert.deepEqual(missingRequiredHeadings(SECTIONED_BASIC), []);
  assert.equal(hasRequiredHeadings(SECTIONED_BASIC), true);
});

test('markdown, parentheticals, colons, and aliases still count as headings', () => {
  const text = `TITLE: Hope

## Main Scripture
Romans 8:28

Brief Summary:
Hope is remembrance.

**Key Points (Comprehensive)**
- One.

### Memorable Elements
A quote.

**Scripture References (Complete):**
None stated
`;
  assert.deepEqual(missingRequiredHeadings(text), []);
});

test('bare-line aliases the client already recognises still count', () => {
  // App Store seed / SummaryDocument: "Main Theme" and "Key Insights".
  const text = `Main Theme
God forms resilient hope.

Key Insights
- Romans 8:28 was framed as a promise.

Memorable Elements
Hope is disciplined remembrance.

Scripture References
Romans 8:28

Main Scripture Text
Romans 8:28
`;
  assert.deepEqual(missingRequiredHeadings(text), []);
});

test('a narrative summary is missing every required heading', () => {
  const missing = missingRequiredHeadings(NARRATIVE);
  assert.deepEqual(missing, [...REQUIRED_HEADINGS]);
  assert.equal(hasRequiredHeadings(NARRATIVE), false);
});

test('a sectioned summary that drops only Scripture References is a miss', () => {
  const withoutRefs = SECTIONED_BASIC.replace(
    '**Scripture References**\n- Romans 8:28\n- Philippians 4:13\n',
    ''
  );
  assert.deepEqual(missingRequiredHeadings(withoutRefs), ['Scripture References']);
});

test('"None stated" under Scripture References still satisfies the heading', () => {
  const noneStated = SECTIONED_BASIC.replace(
    '- Romans 8:28\n- Philippians 4:13\n',
    'None stated\n'
  );
  assert.deepEqual(missingRequiredHeadings(noneStated), []);
});

test('a required heading with content on the same line after **Heading** still counts', () => {
  // The prompt prefers a newline after the heading, but the model sometimes
  // inlines the first sentence: **Brief Summary** Hope is remembrance.
  const text = `TITLE: Hope

**Main Scripture Text** Romans 8:28
**Brief Summary** Hope is disciplined remembrance.
**Key Points** Trust God's hands.
**Memorable Elements** Hope is not denial.
**Scripture References** None stated
`;
  assert.deepEqual(missingRequiredHeadings(text), []);
});

test('a bullet that names a heading is not itself a heading', () => {
  const text = `TITLE: Hope

- **Key Points**: not a heading
- Scripture References: also a bullet
`;
  assert.ok(missingRequiredHeadings(text).includes('Key Points'));
  assert.ok(missingRequiredHeadings(text).includes('Scripture References'));
});

test('completeWithHeadingRetry does not retry a sectioned first response', async () => {
  const calls = [];
  const result = await completeWithHeadingRetry({
    generate: async (attempt) => {
      calls.push(attempt);
      return SECTIONED_BASIC;
    }
  });
  assert.deepEqual(calls, [1]);
  assert.equal(result.retried, false);
  assert.equal(result.content, SECTIONED_BASIC);
  assert.deepEqual(result.missing, []);
});

test('completeWithHeadingRetry retries once when the first response is narrative', async () => {
  const calls = [];
  const result = await completeWithHeadingRetry({
    generate: async (attempt) => {
      calls.push(attempt);
      return attempt === 1 ? NARRATIVE : SECTIONED_BASIC;
    }
  });
  assert.deepEqual(calls, [1, 2]);
  assert.equal(result.retried, true);
  assert.equal(result.content, SECTIONED_BASIC);
  assert.deepEqual(result.missing, [...REQUIRED_HEADINGS]);
});

test('completeWithHeadingRetry returns the second response even if it is still missing headings', async () => {
  const result = await completeWithHeadingRetry({
    generate: async () => NARRATIVE
  });
  assert.equal(result.retried, true);
  assert.equal(result.content, NARRATIVE);
  assert.ok(result.missing.includes('Scripture References'));
});

test('the retry instruction names every missing heading and None stated', () => {
  const message = buildRetryUserMessage(['Scripture References', 'Key Points']);
  assert.match(message, /Scripture References/);
  assert.match(message, /Key Points/);
  assert.match(message, /None stated/);
  for (const heading of REQUIRED_HEADINGS) {
    assert.match(message, new RegExp(heading));
  }
});

test('the prompt contract requires Scripture References even when empty', () => {
  assert.match(MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION, /None stated/i);
  assert.match(MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION, /Scripture References/);
});

test('the production system prompt interpolates the heading contract', () => {
  const prompt = buildSummarizeSystemPrompt({ userTier: 'basic', serviceType: 'Sermon' });
  assert.match(prompt, /User Tier: basic/);
  assert.match(prompt, /Service Type: Sermon/);
  assert.match(prompt, /None stated/i);
  for (const heading of REQUIRED_HEADINGS) {
    assert.match(prompt, new RegExp(heading));
  }
});

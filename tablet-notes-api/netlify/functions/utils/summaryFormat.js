/**
 * TAB-120 stub: heading helpers with the pre-fix behaviour (no validation,
 * no retry). The tests pin the contract; the next edit is the actual check.
 */

const REQUIRED_HEADINGS = [
  'Main Scripture Text',
  'Brief Summary',
  'Key Points',
  'Memorable Elements',
  'Scripture References'
];

const MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION = '';

function missingRequiredHeadings(_text) {
  return [];
}

function hasRequiredHeadings(text) {
  return missingRequiredHeadings(text).length === 0;
}

function buildRetryUserMessage(_missing) {
  return '';
}

async function completeWithHeadingRetry({ generate }) {
  const first = await generate(1);
  return { content: first, retried: false, missing: [] };
}

module.exports = {
  REQUIRED_HEADINGS,
  MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION,
  missingRequiredHeadings,
  hasRequiredHeadings,
  buildRetryUserMessage,
  completeWithHeadingRetry
};

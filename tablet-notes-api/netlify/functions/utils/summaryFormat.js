/**
 * Required-heading contract for `/api/summarize` (TAB-120, option 2).
 *
 * The prompt already asks every tier for a fixed set of sections, but
 * gpt-4o-mini at the default temperature often returns narrative prose and
 * drops Scripture References. The planner (`SummaryDocument` on the client)
 * then has nothing to schedule.
 *
 * Option 2 is the smallest change that can meet 20/20: keep the markdown
 * response shape, require the five basic-tier headings (always include
 * Scripture References, write "None stated" if empty), validate, retry once
 * on a miss. Option 1 (temperature only) cannot guarantee 20/20. Option 3
 * (JSON schema) would change the response contract.
 *
 * Heading aliases match `SummarySectionKind.classify` / `SummaryDocument`
 * so a response the validator accepts is one the client can parse.
 */

const REQUIRED_HEADINGS = [
  'Main Scripture Text',
  'Brief Summary',
  'Key Points',
  'Memorable Elements',
  'Scripture References'
];

const ALIASES_BY_HEADING = {
  'Main Scripture Text': [
    'main scripture text',
    'main scripture',
    'main text',
    'primary scripture',
    'primary text',
    'key scripture',
    'focal scripture',
    'main passage',
    'sermon text'
  ],
  'Brief Summary': [
    'brief summary',
    'summary',
    'main theme',
    'overview',
    'theme',
    'big idea'
  ],
  'Key Points': [
    'key points',
    'main points',
    'key insights',
    'key teaching points'
  ],
  'Memorable Elements': [
    'memorable elements',
    'key quotes',
    'memorable quotes',
    'impact statements',
    'analogies & metaphors',
    'analogies and metaphors',
    'stories & testimonies',
    'stories and testimonies',
    'pastoral challenges',
    'memorable phrasing'
  ],
  'Scripture References': [
    'scripture references',
    'scripture reference',
    'scriptures',
    'supporting scriptures',
    'bible references',
    'references',
    'scriptures referenced'
  ]
};

const MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION =
  'Always include the Scripture References section. If the speaker named no supporting passages, write "None stated".';

const REQUIRED_HEADING_QUALITY_CHECK =
  'Additionally, verify that your summary includes every required heading: ' +
  'Main Scripture Text, Brief Summary, Key Points, Memorable Elements, and Scripture References. ' +
  'Never omit Scripture References. If there are no supporting passages, still include the ' +
  'Scripture References heading and write "None stated".';

function normalizeHeadingName(name) {
  return String(name || '')
    .replace(/\s*\([^)]*\)/g, '')
    .replace(/[*#]/g, '')
    .replace(/:+$/g, '')
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .join(' ');
}

function classifyNormalizedName(normalized) {
  if (!normalized) return null;
  for (const heading of REQUIRED_HEADINGS) {
    if (ALIASES_BY_HEADING[heading].includes(normalized)) return heading;
  }
  return null;
}

/**
 * A line is a required heading in the same forms `SummaryDocument` accepts:
 * `**Heading**`, `## Heading`, a bare line, `**Heading:** content`, or
 * `**Heading** content` on the same line (the model sometimes inlines the
 * first sentence instead of breaking after the heading).
 * List items are never headings.
 */
function requiredHeadingInLine(line) {
  const trimmed = String(line || '').trim();
  if (!trimmed) return null;
  if (/^TITLE:/i.test(trimmed)) return null;
  if (/^[-*+•]\s/.test(trimmed)) return null;

  let text = trimmed;
  if (text.startsWith('#')) {
    text = text.replace(/^#+\s*/, '').trim();
  }

  if (text.startsWith('**')) {
    const close = text.indexOf('**', 2);
    if (close !== -1) {
      const inner = text.slice(2, close);
      return classifyNormalizedName(normalizeHeadingName(inner));
    }
  }

  const colon = text.indexOf(':');
  if (colon !== -1) {
    const classified = classifyNormalizedName(normalizeHeadingName(text.slice(0, colon)));
    if (classified) return classified;
  }

  return classifyNormalizedName(normalizeHeadingName(text));
}

function missingRequiredHeadings(text) {
  const found = new Set();
  for (const line of String(text || '').split(/\r?\n/)) {
    const heading = requiredHeadingInLine(line);
    if (heading) found.add(heading);
  }
  return REQUIRED_HEADINGS.filter((heading) => !found.has(heading));
}

function hasRequiredHeadings(text) {
  return missingRequiredHeadings(text).length === 0;
}

function buildRetryUserMessage(missing) {
  const listed = (missing && missing.length ? missing : REQUIRED_HEADINGS).join(', ');
  return (
    `Your previous response was missing required headings: ${listed}. ` +
    'Rewrite the full summary from scratch. Always include every required heading ' +
    '(Main Scripture Text, Brief Summary, Key Points, Memorable Elements, Scripture References). ' +
    'If there are no supporting passages, still include Scripture References and write "None stated". ' +
    'Keep TITLE: on the first line. Do not return narrative prose without these headings.'
  );
}

/**
 * @param {{ generate: (attempt: 1 | 2) => Promise<string> }} opts
 * @returns {Promise<{ content: string, retried: boolean, missing: string[] }>}
 */
async function completeWithHeadingRetry({ generate }) {
  const first = await generate(1);
  const missing = missingRequiredHeadings(first);
  if (missing.length === 0) {
    return { content: first, retried: false, missing: [] };
  }
  const second = await generate(2);
  return { content: second, retried: true, missing };
}

module.exports = {
  REQUIRED_HEADINGS,
  MANDATORY_SCRIPTURE_REFERENCES_INSTRUCTION,
  REQUIRED_HEADING_QUALITY_CHECK,
  missingRequiredHeadings,
  hasRequiredHeadings,
  buildRetryUserMessage,
  completeWithHeadingRetry
};

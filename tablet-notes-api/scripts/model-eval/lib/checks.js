'use strict';

// Deterministic checks: everything about a summary that can be decided
// without asking another model. Pure functions, unit-tested.

const BOOKS = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth',
  'Samuel', 'Kings', 'Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms', 'Psalm',
  'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Song of Songs', 'Isaiah', 'Jeremiah',
  'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos', 'Obadiah', 'Jonah', 'Micah',
  'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke',
  'John', 'Acts', 'Romans', 'Corinthians', 'Galatians', 'Ephesians', 'Philippians', 'Colossians',
  'Thessalonians', 'Timothy', 'Titus', 'Philemon', 'Hebrews', 'James', 'Peter', 'Jude',
  'Revelations', 'Revelation',
];
const ORDINAL = { first: '1', second: '2', third: '3', i: '1', ii: '2', iii: '3', '1st': '1', '2nd': '2', '3rd': '3' };

const REF_RE = new RegExp(
  '\\b(?:(1st|2nd|3rd|[123]|III|II|I|First|Second|Third)\\s+)?(' + BOOKS.join('|') + ')\\s+(\\d{1,3})(?:\\s*:\\s*(\\d{1,3}))?',
  'gi'
);

function canonBook(prefix, book) {
  let b = book.toLowerCase();
  if (b === 'psalm') b = 'psalms';
  if (b === 'revelations') b = 'revelation';
  if (b === 'song of songs') b = 'song of solomon';
  const p = prefix ? (ORDINAL[prefix.toLowerCase()] || prefix) : '';
  return p ? `${p} ${b}` : b;
}

// Spoken references are how a transcript usually carries scripture:
// "Joshua chapter 14, verse 12", "Romans 8 and verse 28".
function normalizeSpoken(text) {
  return text
    .replace(/\bchapter\s+(\d)/gi, '$1')
    .replace(/(\d{1,3}),?\s*(?:and\s+)?(?:verses?|v\.)\s+(\d{1,3})/gi, '$1:$2');
}

function extractRefs(text) {
  const refs = [];
  const src = normalizeSpoken(text || '');
  for (const m of src.matchAll(REF_RE)) {
    refs.push({ book: canonBook(m[1], m[2]), chapter: m[3], verse: m[4] || null, raw: m[0] });
  }
  return refs;
}

// How well each cited reference is supported by the transcript.
//   book    the book is named somewhere in the transcript
//   chapter that book + chapter appears in the transcript
// A reference to a book the speaker never named is a hallucination.
function groundRefs(outputRefs, transcript) {
  const tRefs = extractRefs(transcript);
  const chapters = new Set(tRefs.map(r => `${r.book} ${r.chapter}`));
  const lower = (transcript || '').toLowerCase();
  const bookNamed = (book) => {
    const bare = book.replace(/^[123] /, '');
    const variants = bare === 'psalms' ? ['psalm'] : bare === 'revelation' ? ['revelation'] : [bare];
    return variants.some(v => new RegExp('\\b' + v, 'i').test(lower));
  };
  const seen = new Set();
  const out = [];
  for (const r of outputRefs) {
    const key = `${r.book} ${r.chapter}:${r.verse || ''}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ ...r, bookGrounded: bookNamed(r.book), chapterGrounded: chapters.has(`${r.book} ${r.chapter}`) });
  }
  return out;
}

const SECTIONS = {
  mainScripture: 'Main Scripture Text',
  briefSummary: 'Brief Summary',
  keyPoints: 'Key Points',
  memorable: 'Memorable Elements',
  scriptureRefs: 'Scripture References',
  application: 'Application',
  deeperDive: 'Deeper Dive',
  studyQuestions: 'Study Questions',
  sermonStructure: 'Sermon Structure',
  relatedInsights: 'Related Insights',
};
const REQUIRED = {
  basic: ['mainScripture', 'briefSummary', 'keyPoints', 'memorable', 'scriptureRefs'],
  premium: ['mainScripture', 'briefSummary', 'keyPoints', 'memorable', 'scriptureRefs', 'application'],
};
const PREMIUM_ONLY = ['application', 'deeperDive', 'studyQuestions', 'sermonStructure', 'relatedInsights'];

const headingRe = (name) => new RegExp('^[ \\t#*>_-]*(?:\\d+[.)]\\s*)?[*_]*' + name.replace(/ /g, '\\s+') + '\\b', 'im');

function findSections(text) {
  const found = {};
  for (const [key, name] of Object.entries(SECTIONS)) {
    const m = headingRe(name).exec(text);
    if (m) found[key] = m.index;
  }
  return found;
}

function sectionBody(text, found, key) {
  if (found[key] == null) return '';
  const start = found[key];
  const next = Object.values(found).filter(i => i > start).sort((a, b) => a - b)[0];
  return text.slice(start, next == null ? undefined : next);
}

// Same shape as the production parser in summarize.js.
function parseTitle(full) {
  const m = (full || '').match(/^(\*\*)?TITLE:\s*(.+?)(?:\n|$)/);
  if (!m) return { ok: false, title: null, words: 0 };
  const title = m[2].trim().replace(/^\*\*|\*\*$/g, '').trim();
  return { ok: title.length > 0, title, words: title.split(/\s+/).filter(Boolean).length };
}

const norm = (s) => s.toLowerCase().replace(/[’‘]/g, "'").replace(/[^a-z0-9']+/g, ' ').trim();

function shingles(words, n) {
  const set = new Set();
  for (let i = 0; i + n <= words.length; i++) set.add(words.slice(i, i + n).join(' '));
  return set;
}

function transcriptIndex(transcript) {
  const text = norm(transcript || '');
  return { text, grams: shingles(text.split(' '), 4) };
}

// A quotation mark is a claim that the speaker said these words.
function checkQuotes(output, index) {
  const quotes = [];
  for (const m of (output || '').matchAll(/[“"]([^“”"\n]{25,400})[”"]/g)) {
    const q = norm(m[1]);
    const words = q.split(' ');
    if (words.length < 6) continue;
    const grams = [...shingles(words, 4)];
    const hit = grams.filter(g => index.grams.has(g)).length / (grams.length || 1);
    const verbatim = index.text.includes(q);
    quotes.push({ text: m[1], verbatim, near: verbatim || hit >= 0.7, overlap: +hit.toFixed(2) });
  }
  return quotes;
}

function checkSummary({ content, finishReason, tier, transcript, index }) {
  const text = content || '';
  const title = parseTitle(text);
  const found = findSections(text);
  const missing = REQUIRED[tier].filter(k => found[k] == null);
  const leaked = tier === 'basic' ? PREMIUM_ONLY.filter(k => found[k] != null) : [];
  const refs = groundRefs(extractRefs(text), transcript);
  const refsInSection = extractRefs(sectionBody(text, found, 'scriptureRefs')).length;
  const quotes = checkQuotes(text, index || transcriptIndex(transcript));

  return {
    completed: text.trim().length > 0 && finishReason === 'stop',
    truncated: finishReason === 'length',
    titleOk: title.ok,
    titleWords: title.words,
    title: title.title,
    missingSections: missing.map(k => SECTIONS[k]),
    sectionsOk: missing.length === 0,
    scriptureSectionHasRef: found.scriptureRefs != null && refsInSection > 0,
    premiumLeak: leaked.map(k => SECTIONS[k]),
    refCount: refs.length,
    refsBookUngrounded: refs.filter(r => !r.bookGrounded).map(r => r.raw),
    refsChapterGrounded: refs.filter(r => r.chapterGrounded).length,
    quoteCount: quotes.length,
    quotesVerbatim: quotes.filter(q => q.verbatim).length,
    quotesNear: quotes.filter(q => q.near).length,
    quotesFabricated: quotes.filter(q => !q.near).map(q => q.text.slice(0, 120)),
    chars: text.length,
  };
}

// chat.js generateQuestions contract: JSON object, "questions" array of exactly `count` strings.
function checkQuestions(content, count = 3) {
  try {
    const data = JSON.parse(content);
    const q = data && data.questions;
    return Array.isArray(q) && q.length === count && q.every(s => typeof s === 'string' && s.trim().length > 10);
  } catch (_) {
    return false;
  }
}

// The chat system prompt requires a redirect for unrelated topics.
function checkOffTopicRedirect(content) {
  const t = (content || '').toLowerCase();
  const redirects = /sermon/.test(t) && /(biblical|bible|scripture|faith)/.test(t);
  return redirects && t.length < 900;
}

module.exports = {
  extractRefs, groundRefs, findSections, sectionBody, parseTitle, transcriptIndex,
  checkQuotes, checkSummary, checkQuestions, checkOffTopicRedirect, SECTIONS,
};

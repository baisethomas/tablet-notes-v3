'use strict';

const test = require('node:test');
const assert = require('node:assert');
const c = require('../lib/checks');
const { loadSummarize, loadChat } = require('../lib/prompt');

const TRANSCRIPT = `Good morning church. Let us pray. Turn with me to Joshua chapter 14, verse 12. Now therefore give me this mountain.
Caleb was eighty-five years old and he said give me this mountain. Paul says in Romans 8 and verse 28 that all things work together for good.
Faith is not the absence of fear, it is obedience in the presence of fear, and I want you to hear that today.`;

const GOOD = `TITLE: Give Me This Mountain

**Main Scripture Text**
Joshua 14:12

**Brief Summary**
Caleb asked for the mountain.

**Key Points**
- Faith at eighty-five.

**Memorable Elements**
- "Faith is not the absence of fear, it is obedience in the presence of fear"

**Scripture References**
- Joshua 14:12
- Romans 8:28
`;

test('extracts written and spoken references', () => {
  const refs = c.extractRefs(TRANSCRIPT);
  assert.deepStrictEqual(refs.map(r => `${r.book} ${r.chapter}:${r.verse}`), ['joshua 14:12', 'romans 8:28']);
  assert.strictEqual(c.extractRefs('1 Corinthians 13:4 and First John 4:8 and Psalm 23')[1].book, '1 john');
  assert.strictEqual(c.extractRefs('Psalm 23')[0].book, 'psalms');
});

test('a clean basic summary passes every deterministic check', () => {
  const r = c.checkSummary({ content: GOOD, finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT });
  assert.ok(r.completed && r.titleOk && r.sectionsOk && r.scriptureSectionHasRef);
  assert.deepStrictEqual(r.refsBookUngrounded, []);
  assert.strictEqual(r.refsChapterGrounded, 2);
  assert.strictEqual(r.quotesVerbatim, 1);
  assert.deepStrictEqual(r.premiumLeak, []);
});

test('flags a book the speaker never named', () => {
  const r = c.checkSummary({ content: GOOD.replace('- Romans 8:28', '- Romans 8:28\n- Hebrews 11:1'), finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT });
  assert.deepStrictEqual(r.refsBookUngrounded, ['Hebrews 11:1']);
});

test('flags a missing Scripture References section (TAB-120)', () => {
  const r = c.checkSummary({ content: GOOD.split('**Scripture References**')[0], finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT });
  assert.ok(!r.sectionsOk);
  assert.deepStrictEqual(r.missingSections, ['Scripture References']);
  assert.ok(!r.scriptureSectionHasRef);
});

test('flags an invented quote, a missing title, truncation, and a premium leak', () => {
  const invented = GOOD.replace(/"Faith is[^"]+"/, '"God will always give you exactly what you ask for in prayer"');
  assert.strictEqual(c.checkSummary({ content: invented, finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT }).quotesFabricated.length, 1);
  assert.ok(!c.checkSummary({ content: GOOD.replace('TITLE: ', ''), finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT }).titleOk);
  assert.ok(!c.checkSummary({ content: GOOD, finishReason: 'length', tier: 'basic', transcript: TRANSCRIPT }).completed);
  const leak = c.checkSummary({ content: GOOD + '\n**Study Questions**\n1. Why?\n', finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT });
  assert.deepStrictEqual(leak.premiumLeak, ['Study Questions']);
  assert.ok(!c.checkSummary({ content: GOOD, finishReason: 'stop', tier: 'premium', transcript: TRANSCRIPT }).sectionsOk, 'premium requires Application');
});

test('markdown-bold title and heading styles are accepted', () => {
  const styled = GOOD.replace('TITLE: Give Me This Mountain', '**TITLE: Give Me This Mountain**').replace(/\*\*((?!TITLE)[^*\n]+)\*\*\n/g, '## $1\n');
  const r = c.checkSummary({ content: styled, finishReason: 'stop', tier: 'basic', transcript: TRANSCRIPT });
  assert.ok(r.titleOk && r.sectionsOk);
  assert.strictEqual(r.title, 'Give Me This Mountain');
});

test('question and off-topic contracts', () => {
  assert.ok(c.checkQuestions('{"questions":["What does this mean for you?","How will you respond today?","Where is your mountain now?"]}'));
  assert.ok(!c.checkQuestions('{"questions":["only one question here?"]}'));
  assert.ok(!c.checkQuestions('```json\n{"questions":[]}\n```'));
  assert.ok(c.checkOffTopicRedirect("I'm designed to help with sermon content and biblical questions. Could you ask something related to this sermon?"));
  assert.ok(!c.checkOffTopicRedirect('You should buy index funds and vote for whoever you like.'));
});

test('off-topic check: redirect language does not excuse an answer', () => {
  const pass = [
    "I'm designed to help with sermon content and biblical questions. Could you ask something related to this sermon?",
    "I can't tell you who to vote for or which stock to buy. I'm here to help with this sermon and related Biblical questions. Is there a part of the message you'd like to explore?",
    "That's outside what I can help with. I focus on the sermon and Scripture, so I won't recommend a candidate or an investment. Would you like to look at the passage the pastor preached from?",
    "I don't give advice on voting for a candidate or buying stocks. Let's return to the sermon: what stood out to you in the Scripture reading?",
  ];
  for (const reply of pass) assert.ok(c.checkOffTopicRedirect(reply), reply);

  const fail = [
    'I can help with Bible and sermon questions, but you should buy index funds and vote for the incumbent.',
    "I'm here for sermon and Scripture questions. That said, index funds are a good bet this week.",
    'My focus is this sermon and biblical topics. Still, I would vote for the candidate who shares your values, and invest in dividend stocks.',
    'Scripture and this sermon are my area, though a wise steward would buy bonds right now.',
    'Let us return to the sermon and the Bible. Briefly: support the Republican candidate.',
    'This sermon is about faith; as for your question, purchase shares of a broad ETF.',
  ];
  for (const reply of fail) {
    assert.ok(!c.checkOffTopicRedirect(reply), reply);
    assert.ok(c.offTopicAdvice(reply).length > 0, reply);
  }
});

test('prompts are read from the live functions', () => {
  const s = loadSummarize();
  const msgs = s.messages({ text: 'x'.repeat(100), serviceType: 'Bible Study', tier: 'premium' });
  assert.match(msgs[0].content, /\*\*User Tier: premium\*\*/);
  assert.match(msgs[0].content, /\*\*Service Type: Bible Study\*\*/);
  assert.ok(msgs[0].content.length > 10000);
  assert.ok(msgs[1].content.startsWith('Please summarize this Bible Study text: '));
  const ch = loadChat();
  assert.match(ch.questions.messages({ title: 't' })[0].content, /^Generate 3 thought-provoking questions/);
  assert.match(ch.chat.messages({ title: 't' }, 'hi')[0].content, /STRICT GUIDELINES/);
});

'use strict';

const { chat } = require('./openrouter');

const SYSTEM = `You are grading a summary of a Christian sermon against the transcript it was written from. The reader of the summary attended the sermon and will rely on the summary as a record of what was actually said. You are not told which system wrote the summary.

Grade strictly from the transcript. Do not reward a summary for sounding good. A claim counts as supported only if you can point to where the speaker said it.

Score each criterion from 1 to 5.

faithfulness: is everything in the summary traceable to the transcript?
  5 = every claim, quote and attribution is supported
  4 = one minor unsupported detail or slight overstatement
  3 = several small unsupported details, or one that changes meaning
  2 = a main point or quote is invented or misattributed
  1 = substantially fabricated

coverage: does it capture the main points the speaker actually made, in order?
  5 = all main points and the call to action; 3 = the theme is right but main points are missing; 1 = misses the message

scripture: is the main passage correctly identified, and are the listed references ones the speaker used?
  5 = main text right, references right and reasonably complete
  3 = main text right but references incomplete or one wrong
  1 = main text wrong or references invented
  If the sermon uses no scripture, score 5 when the summary says so or lists none.

focus: does it leave out opening prayer, greetings and announcements, and keep the teaching?
  5 = clean; 3 = some filler included or a relevant illustration dropped; 1 = mostly filler

clarity: would an attendee find this well organised and useful to revisit?
  5 = clear sections, specific, no padding; 3 = generic or repetitive; 1 = confusing

Return only a JSON object with exactly these keys:
{
  "faithfulness": 1-5, "coverage": 1-5, "scripture": 1-5, "focus": 1-5, "clarity": 1-5,
  "main_scripture_correct": true | false | null,
  "unsupported_claims": ["short description of each claim not supported by the transcript, at most 5"],
  "missed_points": ["main points the summary left out, at most 3"],
  "note": "one sentence"
}`;

const KEYS = ['faithfulness', 'coverage', 'scripture', 'focus', 'clarity'];

function parse(content) {
  const raw = (content || '').replace(/^```(?:json)?\s*|\s*```$/g, '').trim();
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end < 0) return null;
  let data;
  try { data = JSON.parse(raw.slice(start, end + 1)); } catch (_) { return null; }
  for (const k of KEYS) {
    const v = Number(data[k]);
    if (!Number.isFinite(v) || v < 1 || v > 5) return null;
    data[k] = v;
  }
  data.unsupported_claims = Array.isArray(data.unsupported_claims) ? data.unsupported_claims.slice(0, 5) : [];
  data.missed_points = Array.isArray(data.missed_points) ? data.missed_points.slice(0, 3) : [];
  return data;
}

async function judgeSummary(judgeModel, { transcript, serviceType, tier, summary }) {
  const user = `Service type: ${serviceType}
Tier requested: ${tier} (basic summaries are shorter and omit the premium sections; do not penalise that)

<transcript>
${transcript}
</transcript>

<summary>
${summary}
</summary>`;

  for (let attempt = 0; attempt < 2; attempt++) {
    const res = await chat(judgeModel, [
      { role: 'system', content: SYSTEM },
      { role: 'user', content: user },
    ], { temperature: 0, max_tokens: 4000, response_format: { type: 'json_object' } }, { timeoutMs: 180000 });
    if (res.error) {
      if (attempt === 1) return { error: res.error };
      continue;
    }
    const scores = parse(res.content);
    if (scores) return { scores, costUsd: res.usage.costUsd };
    if (attempt === 1) return { error: 'judge returned unparseable output' };
  }
  return { error: 'unreachable' };
}

module.exports = { judgeSummary, KEYS };

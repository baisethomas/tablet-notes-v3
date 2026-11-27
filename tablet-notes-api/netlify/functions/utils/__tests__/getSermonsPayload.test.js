const test = require('node:test');
const assert = require('node:assert/strict');

const { transformSermon, transformSermons } = require('../getSermonsPayload');

const baseSermon = {
  id: 's-1',
  local_id: '11111111-1111-1111-1111-111111111111',
  title: 'A sermon',
  audio_file_url: 'https://example.com/a.m4a',
  audio_file_path: 'user/a.m4a',
  date: '2026-08-16T12:00:00Z',
  service_type: 'Sunday Service',
  speaker: null,
  transcription_status: 'complete',
  summary_status: 'complete',
  is_archived: false,
  user_id: '22222222-2222-2222-2222-222222222222',
  updated_at: '2026-08-16T12:00:00Z'
};

const timedWords = [{ text: 'In', start: 0, end: 200 }];

/**
 * Shipped 1.0.1 `RemoteTranscriptData.segments` is a synthesized `String?`.
 * JSONDecoder throws `Expected to decode String but found an array instead`
 * and aborts the entire `[RemoteSermonData]` pull (TAB-93).
 */
function shipped101DecodeLibrary(sermons) {
  for (const sermon of sermons) {
    const segments = sermon.transcript && sermon.transcript.segments;
    if (segments !== undefined && segments !== null && typeof segments !== 'string') {
      throw new Error('Expected to decode String but found an array instead');
    }
  }
  return sermons;
}

test('jsonb array segments appear on the wire as a JSON string, never as an array', () => {
  // TAB-40: 1.0.2 must receive timings. TAB-93: a JSON array on this key
  // is what dropped the entire get-sermons payload on shipped 1.0.1.
  const sermon = transformSermon({
    ...baseSermon,
    notes: [],
    transcripts: [{
      id: 't-1',
      local_id: '33333333-3333-3333-3333-333333333333',
      text: 'In the beginning',
      segments: timedWords,
      status: 'complete'
    }],
    summaries: []
  });

  assert.equal(sermon.transcript.id, 't-1');
  assert.equal(sermon.transcript.text, 'In the beginning');
  assert.equal(typeof sermon.transcript.segments, 'string');
  assert.equal(Array.isArray(sermon.transcript.segments), false);
  assert.deepEqual(JSON.parse(sermon.transcript.segments), timedWords);
});

test('null and missing segments stay omitted; an existing string is passed through', () => {
  for (const segments of [null, undefined]) {
    const sermon = transformSermon({
      ...baseSermon,
      transcripts: [{
        id: 't-1',
        local_id: '33333333-3333-3333-3333-333333333333',
        text: 'hello',
        segments,
        status: 'complete'
      }]
    });
    assert.equal('segments' in sermon.transcript, false, `segments=${segments}`);
  }

  const alreadyString = transformSermon({
    ...baseSermon,
    transcripts: [{
      id: 't-1',
      local_id: '33333333-3333-3333-3333-333333333333',
      text: 'hello',
      segments: '[]',
      status: 'complete'
    }]
  });
  assert.equal(alreadyString.transcript.segments, '[]');
});

test('a sermon with no transcript still round-trips the rest of the row', () => {
  const sermon = transformSermon({
    ...baseSermon,
    notes: [{ id: 'n-1', local_id: '44444444-4444-4444-4444-444444444444', text: 'note', timestamp: 12 }],
    transcripts: [],
    summaries: {
      id: 'sum-1',
      local_id: '55555555-5555-5555-5555-555555555555',
      title: 'Title',
      text: 'Body',
      type: 'basic',
      status: 'complete'
    }
  });

  assert.equal(sermon.transcript, null);
  assert.equal(sermon.notes.length, 1);
  assert.equal(sermon.notes[0].localId, '44444444-4444-4444-4444-444444444444');
  assert.equal(sermon.summary.id, 'sum-1');
  assert.equal(sermon.localId, baseSermon.local_id);
});

test('one timed transcript cannot drop a sibling sermon', () => {
  const sermons = transformSermons([
    {
      ...baseSermon,
      id: 's-local',
      title: 'August local',
      transcripts: [{
        id: 't-local',
        local_id: '33333333-3333-3333-3333-333333333333',
        text: 'hello',
        segments: null,
        status: 'complete'
      }]
    },
    {
      ...baseSermon,
      id: 's-old',
      title: 'Older cloud sermon',
      transcripts: [{
        id: 't-old',
        local_id: '33333333-3333-3333-3333-333333333333',
        text: 'In the beginning',
        segments: [{ text: 'Hello', start: 0, end: 400 }],
        status: 'complete'
      }]
    }
  ]);

  assert.deepEqual(sermons.map((s) => s.title), ['August local', 'Older cloud sermon']);
  assert.equal('segments' in sermons[0].transcript, false);
  assert.equal(typeof sermons[1].transcript.segments, 'string');
  assert.equal(Array.isArray(sermons[1].transcript.segments), false);
});

test('shipped 1.0.1 String? decoder still imports a library that includes a timed transcript', () => {
  const sermons = transformSermons([
    {
      ...baseSermon,
      id: 's-local',
      title: 'August local',
      transcripts: [{
        id: 't-local',
        local_id: '33333333-3333-3333-3333-333333333333',
        text: 'hello',
        segments: null,
        status: 'complete'
      }]
    },
    {
      ...baseSermon,
      id: 's-old',
      title: 'Older cloud sermon',
      transcripts: [{
        id: 't-old',
        local_id: '33333333-3333-3333-3333-333333333333',
        text: 'In the beginning',
        segments: [{ text: 'Hello', start: 0, end: 400 }],
        status: 'complete'
      }]
    }
  ]);

  const decoded = shipped101DecodeLibrary(sermons);
  assert.equal(decoded.length, 2);
  assert.equal(typeof decoded[1].transcript.segments, 'string');
  assert.deepEqual(JSON.parse(decoded[1].transcript.segments), [{ text: 'Hello', start: 0, end: 400 }]);
});

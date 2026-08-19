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

test('jsonb array segments never appear on the wire', () => {
  // Shipped clients decode segments as String?. An array here is what
  // dropped the entire get-sermons payload (TAB-93).
  const sermon = transformSermon({
    ...baseSermon,
    notes: [],
    transcripts: [{
      id: 't-1',
      local_id: '33333333-3333-3333-3333-333333333333',
      text: 'In the beginning',
      segments: [{ text: 'In', start: 0, end: 0.2 }],
      status: 'complete'
    }],
    summaries: []
  });

  assert.equal(sermon.transcript.id, 't-1');
  assert.equal(sermon.transcript.text, 'In the beginning');
  assert.equal('segments' in sermon.transcript, false);
});

test('null and string segments are omitted too', () => {
  for (const segments of [null, '[]', undefined]) {
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
        segments: [{ text: 'Hello', start: 0, end: 0.4 }],
        status: 'complete'
      }]
    }
  ]);

  assert.deepEqual(sermons.map((s) => s.title), ['August local', 'Older cloud sermon']);
  assert.equal('segments' in sermons[0].transcript, false);
  assert.equal('segments' in sermons[1].transcript, false);
});

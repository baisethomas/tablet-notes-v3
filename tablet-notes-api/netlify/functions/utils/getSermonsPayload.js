/**
 * Shape `get-sermons` rows into the client `RemoteSermonData` payload.
 *
 * `transcripts.segments` is jsonb in production. Shipped 1.0.1 decodes it as
 * a synthesized `String?`, so a JSON array fails the entire library import
 * (TAB-93). TAB-40 therefore stringifies the JSONB onto the existing
 * `segments` key: 1.0.1's String? succeeds and ignores the value; 1.0.2
 * parses the string into timings. Null/missing stay omitted. No schema
 * change and no production backfill of rows already stored as null.
 */

function firstChild(value) {
  if (Array.isArray(value)) {
    return value[0] || null;
  }
  if (value && typeof value === 'object') {
    return value;
  }
  return null;
}

function childCount(value) {
  if (Array.isArray(value)) {
    return value.length;
  }
  return value ? 1 : 0;
}

function transformNotes(notes) {
  if (!notes) {
    return [];
  }
  const list = Array.isArray(notes) ? notes : [notes];
  return list.map((note) => ({
    id: note.id,
    localId: note.local_id,
    text: note.text,
    timestamp: note.timestamp
  }));
}

function wireSegments(segments) {
  if (segments == null) {
    return undefined;
  }
  if (typeof segments === 'string') {
    return segments;
  }
  try {
    return JSON.stringify(segments);
  } catch {
    return undefined;
  }
}

function transformTranscript(transcripts) {
  const row = firstChild(transcripts);
  if (!row) {
    return null;
  }
  const payload = {
    id: row.id,
    localId: row.local_id,
    text: row.text,
    status: row.status
  };
  const segments = wireSegments(row.segments);
  if (segments !== undefined) {
    payload.segments = segments;
  }
  return payload;
}

function transformSummary(summaries) {
  const row = firstChild(summaries);
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    localId: row.local_id,
    title: row.title,
    text: row.text,
    type: row.type,
    status: row.status
  };
}

function transformSermon(sermon) {
  return {
    id: sermon.id,
    localId: sermon.local_id,
    title: sermon.title,
    audioFileURL: sermon.audio_file_url,
    audioFilePath: sermon.audio_file_path,
    date: sermon.date,
    serviceType: sermon.service_type,
    speaker: sermon.speaker,
    transcriptionStatus: sermon.transcription_status,
    summaryStatus: sermon.summary_status,
    isArchived: sermon.is_archived,
    userId: sermon.user_id,
    updatedAt: sermon.updated_at,
    notes: transformNotes(sermon.notes),
    transcript: transformTranscript(sermon.transcripts),
    summary: transformSummary(sermon.summaries)
  };
}

function transformSermons(rows) {
  return (rows || []).map(transformSermon);
}

module.exports = {
  childCount,
  firstChild,
  transformSermon,
  transformSermons,
  wireSegments
};

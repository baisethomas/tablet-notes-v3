/**
 * Inserts the child records (notes, transcript, summary) for a freshly
 * created sermon row and reports which scopes actually made it.
 *
 * A scope is acknowledged (true) when its insert succeeded or there was
 * nothing to insert. The client clears local dirty flags only for
 * acknowledged scopes, so a failed child insert is re-pushed on the next
 * sync instead of being silently lost (TAB-34).
 */
async function createSermonChildren({ supabase, body, sermonId, userId, logger }) {
  const syncedScopes = {
    metadata: true,
    notes: true,
    transcript: true,
    summary: true
  };

  if (body.notes && Array.isArray(body.notes) && body.notes.length > 0) {
    logger.info('Creating notes', { count: body.notes.length, sermonId });
    const notesData = body.notes.map(note => ({
      local_id: note.id,
      sermon_id: sermonId,
      user_id: userId,
      text: note.text,
      timestamp: note.timestamp ?? 0
    }));

    const { data: insertedNotes, error: notesError } = await supabase
      .from('notes')
      .insert(notesData)
      .select();

    if (notesError) {
      syncedScopes.notes = false;
      logger.error('Failed to create notes', {
        sermonId,
        error: notesError.message,
        code: notesError.code,
        details: notesError.details
      });
    } else {
      logger.info('Successfully created notes', {
        sermonId,
        count: insertedNotes?.length || 0
      });
    }
  }

  if (body.transcript && body.transcript.text) {
    logger.info('Creating transcript', {
      sermonId,
      textLength: body.transcript.text?.length || 0,
      hasId: !!body.transcript.id
    });
    const transcriptData = {
      local_id: body.transcript.id,
      sermon_id: sermonId,
      user_id: userId,
      text: body.transcript.text,
      segments: body.transcript.segments || null,
      status: body.transcript.status || 'complete'
    };

    const { data: insertedTranscript, error: transcriptError } = await supabase
      .from('transcripts')
      .insert(transcriptData)
      .select();

    if (transcriptError) {
      syncedScopes.transcript = false;
      logger.error('Failed to create transcript', {
        sermonId,
        error: transcriptError.message,
        code: transcriptError.code,
        details: transcriptError.details
      });
    } else {
      logger.info('Successfully created transcript', {
        sermonId,
        transcriptId: insertedTranscript?.[0]?.id
      });
    }
  } else {
    logger.info('No transcript to create', {
      sermonId,
      hasTranscript: !!body.transcript,
      hasText: !!(body.transcript && body.transcript.text)
    });
  }

  if (body.summary && body.summary.text) {
    logger.info('Creating summary', {
      sermonId,
      textLength: body.summary.text?.length || 0,
      title: body.summary.title || '(no title)',
      hasId: !!body.summary.id
    });
    const summaryData = {
      local_id: body.summary.id,
      sermon_id: sermonId,
      user_id: userId,
      title: body.summary.title || '',
      text: body.summary.text,
      type: body.summary.type || 'devotional',
      status: body.summary.status || 'complete'
    };

    const { data: insertedSummary, error: summaryError } = await supabase
      .from('summaries')
      .insert(summaryData)
      .select();

    if (summaryError) {
      syncedScopes.summary = false;
      logger.error('Failed to create summary', {
        sermonId,
        error: summaryError.message,
        code: summaryError.code,
        details: summaryError.details
      });
    } else {
      logger.info('Successfully created summary', {
        sermonId,
        summaryId: insertedSummary?.[0]?.id
      });
    }
  } else {
    logger.info('No summary to create', {
      sermonId,
      hasSummary: !!body.summary,
      hasText: !!(body.summary && body.summary.text)
    });
  }

  return syncedScopes;
}

module.exports = { createSermonChildren };

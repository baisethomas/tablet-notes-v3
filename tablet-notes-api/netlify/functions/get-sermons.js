const { createClient } = require('@supabase/supabase-js');
const { handleCORS, createAuthMiddleware, createErrorResponse, createSuccessResponse } = require('./utils/security');
const { withLogging } = require('./utils/logger');

exports.handler = withLogging('get-sermons', async (event, context) => {
  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'GET') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  // Apply authentication
  const authMiddleware = createAuthMiddleware();
  const authResponse = await authMiddleware(event);
  if (authResponse) {
    return authResponse;
  }

  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !supabaseKey) {
      return createErrorResponse(new Error('Server configuration error'), 500);
    }
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Parse userId from query string
    const userId = event.queryStringParameters && event.queryStringParameters.userId;
    if (!userId) {
      return createErrorResponse(new Error('Missing userId'), 400);
    }

    // Fetch all sermons for the user with related data
    const { data, error } = await supabase
      .from('sermons')
      .select(`
        id,
        local_id,
        title,
        audio_file_url,
        audio_file_path,
        audio_file_name,
        date,
        service_type,
        speaker,
        transcription_status,
        summary_status,
        is_archived,
        user_id,
        updated_at,
        created_at,
        notes (
          id,
          local_id,
          text,
          timestamp
        ),
        transcripts (
          id,
          local_id,
          text,
          segments,
          status
        ),
        summaries (
          id,
          local_id,
          title,
          text,
          type,
          status
        )
      `)
      .eq('user_id', userId)
      .order('date', { ascending: false });

    if (error) {
      logger.error('Failed to fetch sermons', {
        userId,
        error: error.message,
        code: error.code,
        details: error.details
      });
      return createErrorResponse(new Error(error.message), 500);
    }

    logger.info('Fetched sermons from database', {
      userId,
      count: data?.length || 0,
      sermonIds: data?.map(s => s.id) || []
    });

    // Log raw data for debugging
    if (data && data.length > 0) {
      data.forEach(sermon => {
        logger.info('Sermon data', {
          sermonId: sermon.id,
          title: sermon.title,
          notesCount: sermon.notes?.length || 0,
          transcriptsCount: sermon.transcripts?.length || 0,
          summariesCount: sermon.summaries?.length || 0,
          hasNotes: !!sermon.notes && sermon.notes.length > 0,
          hasTranscripts: !!sermon.transcripts && sermon.transcripts.length > 0,
          hasSummaries: !!sermon.summaries && sermon.summaries.length > 0
        });
      });
    }

    // Transform data to match RemoteSermonData structure
    const sermons = data.map(sermon => {
      const transformed = {
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
      notes: sermon.notes ? sermon.notes.map(note => ({
        id: note.id,
        localId: note.local_id,
        text: note.text,
        timestamp: note.timestamp
      })) : [],
      transcript: sermon.transcripts && sermon.transcripts.length > 0 ? {
        id: sermon.transcripts[0].id,
        localId: sermon.transcripts[0].local_id,
        text: sermon.transcripts[0].text,
        segments: sermon.transcripts[0].segments,
        status: sermon.transcripts[0].status
      } : null,
      summary: sermon.summaries && sermon.summaries.length > 0 ? {
        id: sermon.summaries[0].id,
        localId: sermon.summaries[0].local_id,
        title: sermon.summaries[0].title,
        text: sermon.summaries[0].text,
        type: sermon.summaries[0].type,
        status: sermon.summaries[0].status
      } : null
      };

      // Log transformation result for debugging
      logger.info('Transformed sermon', {
        sermonId: transformed.id,
        notesCount: transformed.notes.length,
        hasTranscript: !!transformed.transcript,
        hasSummary: !!transformed.summary,
        transcriptId: transformed.transcript?.id,
        summaryId: transformed.summary?.id
      });

      return transformed;
    });

    logger.info('Returning sermons', {
      userId,
      count: sermons.length,
      sermonsWithTranscript: sermons.filter(s => s.transcript).length,
      sermonsWithSummary: sermons.filter(s => s.summary).length,
      sermonsWithNotes: sermons.filter(s => s.notes.length > 0).length
    });

    return createSuccessResponse(sermons, 200);
  } catch (error) {
    return createErrorResponse(error, 500);
  }
}); 
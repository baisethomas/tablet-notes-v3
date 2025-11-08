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
      event.logger.error('Failed to fetch sermons', {
        userId,
        error: error.message,
        code: error.code,
        details: error.details
      });
      return createErrorResponse(new Error(error.message), 500);
    }

    // Handle null/undefined data
    if (!data) {
      event.logger.warn('No data returned from query', { userId });
      return createSuccessResponse([], 200);
    }

    event.logger.info('Fetched sermons from database', {
      userId,
      count: data?.length || 0,
      sermonIds: data?.map(s => s.id) || []
    });

    // Log raw data for debugging
    if (data && data.length > 0) {
      data.forEach(sermon => {
        event.logger.info('Sermon raw data', {
          sermonId: sermon.id,
          title: sermon.title,
          notesCount: Array.isArray(sermon.notes) ? sermon.notes.length : (sermon.notes ? 1 : 0),
          transcriptsCount: Array.isArray(sermon.transcripts) ? sermon.transcripts.length : (sermon.transcripts ? 1 : 0),
          summariesCount: Array.isArray(sermon.summaries) ? sermon.summaries.length : (sermon.summaries ? 1 : 0),
          hasNotes: !!sermon.notes && (Array.isArray(sermon.notes) ? sermon.notes.length > 0 : true),
          hasTranscripts: !!sermon.transcripts && (Array.isArray(sermon.transcripts) ? sermon.transcripts.length > 0 : true),
          hasSummaries: !!sermon.summaries && (Array.isArray(sermon.summaries) ? sermon.summaries.length > 0 : true),
          notesType: Array.isArray(sermon.notes) ? 'array' : (sermon.notes ? 'object' : 'null'),
          notesArray: sermon.notes,
          transcriptsArray: sermon.transcripts,
          summariesArray: sermon.summaries
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
        transcript: sermon.transcripts && (Array.isArray(sermon.transcripts) ? sermon.transcripts.length > 0 : typeof sermon.transcripts === 'object') ? {
          id: Array.isArray(sermon.transcripts) ? sermon.transcripts[0].id : sermon.transcripts.id,
          localId: Array.isArray(sermon.transcripts) ? sermon.transcripts[0].local_id : sermon.transcripts.local_id,
          text: Array.isArray(sermon.transcripts) ? sermon.transcripts[0].text : sermon.transcripts.text,
          segments: Array.isArray(sermon.transcripts) ? sermon.transcripts[0].segments : sermon.transcripts.segments,
          status: Array.isArray(sermon.transcripts) ? sermon.transcripts[0].status : sermon.transcripts.status
        } : null,
        summary: sermon.summaries && (Array.isArray(sermon.summaries) ? sermon.summaries.length > 0 : typeof sermon.summaries === 'object') ? {
          id: Array.isArray(sermon.summaries) ? sermon.summaries[0].id : sermon.summaries.id,
          localId: Array.isArray(sermon.summaries) ? sermon.summaries[0].local_id : sermon.summaries.local_id,
          title: Array.isArray(sermon.summaries) ? sermon.summaries[0].title : sermon.summaries.title,
          text: Array.isArray(sermon.summaries) ? sermon.summaries[0].text : sermon.summaries.text,
          type: Array.isArray(sermon.summaries) ? sermon.summaries[0].type : sermon.summaries.type,
          status: Array.isArray(sermon.summaries) ? sermon.summaries[0].status : sermon.summaries.status
        } : null
      };

      // Log transformation result for debugging
      event.logger.info('Transformed sermon', {
        sermonId: transformed.id,
        notesCount: transformed.notes.length,
        hasTranscript: !!transformed.transcript,
        hasSummary: !!transformed.summary,
        transcriptId: transformed.transcript?.id,
        summaryId: transformed.summary?.id,
        transcriptTextLength: transformed.transcript?.text?.length || 0,
        summaryTextLength: transformed.summary?.text?.length || 0
      });

      return transformed;
    });

    event.logger.info('Returning sermons summary', {
      userId,
      totalCount: sermons.length,
      sermonsWithTranscript: sermons.filter(s => s.transcript).length,
      sermonsWithSummary: sermons.filter(s => s.summary).length,
      sermonsWithNotes: sermons.filter(s => s.notes.length > 0).length
    });

    return createSuccessResponse(sermons, 200);
  } catch (error) {
    event.logger.error('Unexpected error in get-sermons', {
      error: error.message,
      stack: error.stack
    }, error);
    return createErrorResponse(error, 500);
  }
}); 
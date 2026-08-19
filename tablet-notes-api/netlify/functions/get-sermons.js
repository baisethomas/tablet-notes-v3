const { createClient } = require('@supabase/supabase-js');
const { handleCORS, createAuthMiddleware, createErrorResponse, createSuccessResponse } = require('./utils/security');
const { withLogging } = require('./utils/logger');
const { childCount, transformSermons } = require('./utils/getSermonsPayload');

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

    // Counts only — never log child row bodies. `transcripts.segments` jsonb
    // arrays are ~1.5MB for a typical library and used to be dumped here.
    event.logger.info('Sermon child counts', {
      userId,
      rows: data.map((sermon) => ({
        sermonId: sermon.id,
        notes: childCount(sermon.notes),
        transcripts: childCount(sermon.transcripts),
        summaries: childCount(sermon.summaries)
      }))
    });

    const sermons = transformSermons(data);

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

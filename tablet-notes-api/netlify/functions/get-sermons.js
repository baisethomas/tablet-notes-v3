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
      return createErrorResponse(new Error(error.message), 500);
    }

    // Transform data to match RemoteSermonData structure
    const sermons = data.map(sermon => ({
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
      notes: sermon.notes || [],
      transcript: sermon.transcripts && sermon.transcripts.length > 0 ? sermon.transcripts[0] : null,
      summary: sermon.summaries && sermon.summaries.length > 0 ? sermon.summaries[0] : null
    }));

    return createSuccessResponse(sermons, 200);
  } catch (error) {
    return createErrorResponse(error, 500);
  }
}); 
const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');
const { Validator } = require('./utils/validator');

exports.handler = withLogging('create-sermon', async (event, context) => {
  const logger = event.logger;

  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'POST') {
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
      logger.error('Missing Supabase configuration');
      return createErrorResponse(new Error('Server configuration error'), 500);
    }

    const supabase = createClient(supabaseUrl, supabaseKey);
    const user = event.user;

    // Parse request body
    const body = JSON.parse(event.body || '{}');

    // Validate required fields
    const requiredFields = ['localId', 'title', 'date', 'serviceType', 'audioFileName'];
    for (const field of requiredFields) {
      if (!body[field]) {
        return createErrorResponse(new Error(`Missing required field: ${field}`), 400);
      }
    }

    // Prepare sermon data
    const sermonData = {
      local_id: body.localId,
      user_id: user.id,
      title: body.title,
      date: body.date,
      service_type: body.serviceType,
      speaker: body.speaker || null,
      audio_file_name: body.audioFileName,
      audio_file_url: body.audioFileUrl || null,
      audio_file_size_bytes: body.audioFileSizeBytes || null,
      audio_file_path: body.audioFilePath || body.audioFileName,
      duration: body.duration || 0,
      transcription_status: body.transcriptionStatus || 'pending',
      summary_status: body.summaryStatus || 'pending',
      is_archived: body.isArchived || false,
      sync_status: 'synced',
      updated_at: body.updatedAt || new Date().toISOString()
    };

    logger.info('Creating sermon', {
      userId: user.id,
      localId: body.localId,
      title: body.title
    });

    // Insert sermon into database
    const { data: sermon, error: insertError } = await supabase
      .from('sermons')
      .insert(sermonData)
      .select()
      .single();

    if (insertError) {
      logger.error('Failed to create sermon', {
        error: insertError.message,
        code: insertError.code
      });

      // Handle unique constraint violation (sermon already exists)
      if (insertError.code === '23505') {
        return createErrorResponse(new Error('Sermon with this ID already exists'), 409);
      }

      return createErrorResponse(new Error(insertError.message), 500);
    }

    // Create related records if provided
    if (body.notes && Array.isArray(body.notes)) {
      const notesData = body.notes.map(note => ({
        local_id: note.id,
        sermon_id: sermon.id,
        user_id: user.id,
        text: note.text,
        timestamp: note.timestamp
      }));

      const { error: notesError } = await supabase
        .from('notes')
        .insert(notesData);

      if (notesError) {
        logger.warn('Failed to create some notes', {
          sermonId: sermon.id,
          error: notesError.message
        });
      }
    }

    if (body.transcript) {
      const transcriptData = {
        local_id: body.transcript.id,
        sermon_id: sermon.id,
        user_id: user.id,
        text: body.transcript.text,
        segments: body.transcript.segments || null,
        status: body.transcript.status || 'complete'
      };

      const { error: transcriptError } = await supabase
        .from('transcripts')
        .insert(transcriptData);

      if (transcriptError) {
        logger.warn('Failed to create transcript', {
          sermonId: sermon.id,
          error: transcriptError.message
        });
      }
    }

    if (body.summary) {
      const summaryData = {
        local_id: body.summary.id,
        sermon_id: sermon.id,
        user_id: user.id,
        title: body.summary.title || '',
        text: body.summary.text,
        type: body.summary.type || 'devotional',
        status: body.summary.status || 'complete'
      };

      const { error: summaryError } = await supabase
        .from('summaries')
        .insert(summaryData);

      if (summaryError) {
        logger.warn('Failed to create summary', {
          sermonId: sermon.id,
          error: summaryError.message
        });
      }
    }

    logger.info('Sermon created successfully', {
      userId: user.id,
      sermonId: sermon.id,
      remoteId: sermon.id
    });

    return createSuccessResponse({
      id: sermon.id,
      localId: sermon.local_id,
      createdAt: sermon.created_at,
      updatedAt: sermon.updated_at
    }, 201);

  } catch (error) {
    logger.error('Sermon creation failed', {
      userId: event.user?.id,
      error: error.message,
      stack: error.stack
    });
    return createErrorResponse(error, 500);
  }
});

const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

exports.handler = withLogging('update-sermon', async (event, context) => {
  const logger = event.logger;

  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'PUT' && event.httpMethod !== 'PATCH') {
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

    // Validate required field
    if (!body.remoteId) {
      return createErrorResponse(new Error('Missing required field: remoteId'), 400);
    }

    logger.info('Updating sermon', {
      userId: user.id,
      remoteId: body.remoteId,
      localId: body.localId
    });

    // Verify sermon belongs to user
    const { data: existingSermon, error: fetchError } = await supabase
      .from('sermons')
      .select('id, user_id')
      .eq('id', body.remoteId)
      .single();

    if (fetchError || !existingSermon) {
      logger.warn('Sermon not found', { remoteId: body.remoteId });
      return createErrorResponse(new Error('Sermon not found'), 404);
    }

    if (existingSermon.user_id !== user.id) {
      logger.security('unauthorized_update_attempt', {
        userId: user.id,
        sermonUserId: existingSermon.user_id,
        remoteId: body.remoteId
      });
      return createErrorResponse(new Error('Unauthorized'), 403);
    }

    // Prepare update data (only include fields that are provided)
    const updateData = {};

    if (body.title !== undefined) updateData.title = body.title;
    if (body.date !== undefined) updateData.date = body.date;
    if (body.serviceType !== undefined) updateData.service_type = body.serviceType;
    if (body.speaker !== undefined) updateData.speaker = body.speaker;
    if (body.audioFileName !== undefined) updateData.audio_file_name = body.audioFileName;
    if (body.audioFileUrl !== undefined) updateData.audio_file_url = body.audioFileUrl;
    if (body.audioFileSizeBytes !== undefined) updateData.audio_file_size_bytes = body.audioFileSizeBytes;
    if (body.transcriptionStatus !== undefined) updateData.transcription_status = body.transcriptionStatus;
    if (body.summaryStatus !== undefined) updateData.summary_status = body.summaryStatus;
    if (body.isArchived !== undefined) updateData.is_archived = body.isArchived;

    // Always update the timestamp
    updateData.updated_at = body.updatedAt || new Date().toISOString();

    // Update sermon in database
    const { data: sermon, error: updateError } = await supabase
      .from('sermons')
      .update(updateData)
      .eq('id', body.remoteId)
      .eq('user_id', user.id)
      .select()
      .single();

    if (updateError) {
      logger.error('Failed to update sermon', {
        error: updateError.message,
        code: updateError.code,
        remoteId: body.remoteId
      });
      return createErrorResponse(new Error(updateError.message), 500);
    }

    // Update notes if provided
    if (body.notes && Array.isArray(body.notes)) {
      // Delete existing notes
      await supabase
        .from('notes')
        .delete()
        .eq('sermon_id', body.remoteId);

      // Insert new notes
      if (body.notes.length > 0) {
        const notesData = body.notes.map(note => ({
          local_id: note.id,
          sermon_id: body.remoteId,
          user_id: user.id,
          text: note.text,
          timestamp: note.timestamp
        }));

        const { error: notesError } = await supabase
          .from('notes')
          .insert(notesData);

        if (notesError) {
          logger.warn('Failed to update notes', {
            sermonId: body.remoteId,
            error: notesError.message
          });
        }
      }
    }

    // Update transcript if provided
    if (body.transcript) {
      const transcriptData = {
        local_id: body.transcript.id,
        sermon_id: body.remoteId,
        user_id: user.id,
        text: body.transcript.text,
        segments: body.transcript.segments || null,
        status: body.transcript.status || 'complete'
      };

      const { error: transcriptError } = await supabase
        .from('transcripts')
        .upsert(transcriptData, {
          onConflict: 'sermon_id'
        });

      if (transcriptError) {
        logger.warn('Failed to update transcript', {
          sermonId: body.remoteId,
          error: transcriptError.message
        });
      }
    }

    // Update summary if provided
    if (body.summary) {
      const summaryData = {
        local_id: body.summary.id,
        sermon_id: body.remoteId,
        user_id: user.id,
        title: body.summary.title || '',
        text: body.summary.text,
        type: body.summary.type || 'devotional',
        status: body.summary.status || 'complete'
      };

      const { error: summaryError } = await supabase
        .from('summaries')
        .upsert(summaryData, {
          onConflict: 'sermon_id'
        });

      if (summaryError) {
        logger.warn('Failed to update summary', {
          sermonId: body.remoteId,
          error: summaryError.message
        });
      }
    }

    logger.info('Sermon updated successfully', {
      userId: user.id,
      sermonId: sermon.id
    });

    return createSuccessResponse({
      id: sermon.id,
      updatedAt: sermon.updated_at
    }, 200);

  } catch (error) {
    logger.error('Sermon update failed', {
      userId: event.user?.id,
      error: error.message,
      stack: error.stack
    });
    return createErrorResponse(error, 500);
  }
});

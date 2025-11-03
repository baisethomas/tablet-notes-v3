const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

exports.handler = withLogging('delete-sermon', async (event, context) => {
  const logger = event.logger;

  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'DELETE') {
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

    // Get sermon ID from query parameters
    const sermonId = event.queryStringParameters?.sermonId;

    if (!sermonId) {
      return createErrorResponse(new Error('Missing required parameter: sermonId'), 400);
    }

    logger.info('Deleting sermon', {
      userId: user.id,
      sermonId: sermonId
    });

    // Verify sermon belongs to user before deleting
    const { data: existingSermon, error: fetchError } = await supabase
      .from('sermons')
      .select('id, user_id, audio_file_url')
      .eq('id', sermonId)
      .single();

    if (fetchError || !existingSermon) {
      logger.warn('Sermon not found', { sermonId });
      return createErrorResponse(new Error('Sermon not found'), 404);
    }

    if (existingSermon.user_id !== user.id) {
      logger.security('unauthorized_delete_attempt', {
        userId: user.id,
        sermonUserId: existingSermon.user_id,
        sermonId: sermonId
      });
      return createErrorResponse(new Error('Unauthorized'), 403);
    }

    // Delete audio file from storage if it exists
    if (existingSermon.audio_file_url) {
      try {
        // Extract file path from URL
        const urlParts = existingSermon.audio_file_url.split('/sermon-audio/');
        if (urlParts.length > 1) {
          const filePath = urlParts[1];

          const { error: storageError } = await supabase
            .storage
            .from('sermon-audio')
            .remove([filePath]);

          if (storageError) {
            logger.warn('Failed to delete audio file from storage', {
              sermonId,
              error: storageError.message
            });
            // Continue with sermon deletion even if storage delete fails
          } else {
            logger.info('Audio file deleted from storage', {
              sermonId,
              filePath
            });
          }
        }
      } catch (storageError) {
        logger.warn('Error deleting audio file', {
          sermonId,
          error: storageError.message
        });
        // Continue with sermon deletion
      }
    }

    // Delete sermon from database (CASCADE will delete related notes, transcripts, summaries)
    const { error: deleteError } = await supabase
      .from('sermons')
      .delete()
      .eq('id', sermonId)
      .eq('user_id', user.id);

    if (deleteError) {
      logger.error('Failed to delete sermon', {
        error: deleteError.message,
        code: deleteError.code,
        sermonId
      });
      return createErrorResponse(new Error(deleteError.message), 500);
    }

    logger.info('Sermon deleted successfully', {
      userId: user.id,
      sermonId
    });

    return createSuccessResponse({
      deleted: true,
      sermonId
    }, 200);

  } catch (error) {
    logger.error('Sermon deletion failed', {
      userId: event.user?.id,
      error: error.message,
      stack: error.stack
    });
    return createErrorResponse(error, 500);
  }
});

const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

const STORAGE_BUCKET = 'sermon-audio';
const STORAGE_PAGE_SIZE = 100;

/**
 * Delete every object in the user's storage folder.
 * Storage objects are not covered by Postgres cascades, so they must be
 * removed explicitly before the auth user is deleted.
 */
async function deleteUserStorageObjects(supabase, userId, logger) {
  let deletedCount = 0;

  // Re-list from the start each iteration since removals shift pagination
  for (;;) {
    const { data: files, error: listError } = await supabase
      .storage
      .from(STORAGE_BUCKET)
      .list(userId, { limit: STORAGE_PAGE_SIZE });

    if (listError) {
      throw new Error(`Failed to list storage objects: ${listError.message}`);
    }

    if (!files || files.length === 0) {
      break;
    }

    const paths = files.map((file) => `${userId}/${file.name}`);
    const { error: removeError } = await supabase
      .storage
      .from(STORAGE_BUCKET)
      .remove(paths);

    if (removeError) {
      throw new Error(`Failed to delete storage objects: ${removeError.message}`);
    }

    deletedCount += paths.length;

    if (files.length < STORAGE_PAGE_SIZE) {
      break;
    }
  }

  logger.info('Deleted user storage objects', { userId, deletedCount });
  return deletedCount;
}

exports.handler = withLogging('delete-account', async (event, context) => {
  const logger = event.logger;

  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'DELETE') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  // Apply authentication — the account being deleted is always the caller's own
  const authMiddleware = createAuthMiddleware();
  const authResponse = await authMiddleware(event);
  if (authResponse) {
    return authResponse;
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    logger.error('Missing Supabase configuration');
    return createErrorResponse(new Error('Server configuration error'), 500);
  }

  const supabase = createClient(supabaseUrl, supabaseKey);
  const userId = event.user.id;

  logger.info('Starting account deletion', { userId });

  try {
    // 1. Storage objects (not covered by DB cascades)
    await deleteUserStorageObjects(supabase, userId, logger);

    // 2. Database rows. Sermons cascade to notes/transcripts/summaries.
    //    Deleting explicitly (rather than relying on the auth-user cascade)
    //    guarantees the data is gone even if a FK is missing ON DELETE CASCADE.
    const { error: sermonsError } = await supabase
      .from('sermons')
      .delete()
      .eq('user_id', userId);

    if (sermonsError) {
      throw new Error(`Failed to delete sermons: ${sermonsError.message}`);
    }

    const { error: profileError } = await supabase
      .from('profiles')
      .delete()
      .eq('id', userId);

    if (profileError) {
      throw new Error(`Failed to delete profile: ${profileError.message}`);
    }

    // 3. Auth user last — after this the user can no longer sign in
    const { error: authError } = await supabase.auth.admin.deleteUser(userId);

    if (authError) {
      throw new Error(`Failed to delete auth user: ${authError.message}`);
    }

    logger.info('Account deletion completed', { userId });

    return createSuccessResponse({
      deleted: true,
      userId
    }, 200);

  } catch (error) {
    logger.error('Account deletion failed', {
      userId,
      error: error.message,
      stack: error.stack
    });
    return createErrorResponse(new Error('Account deletion failed'), 500);
  }
});

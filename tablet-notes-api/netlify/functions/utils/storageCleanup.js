/**
 * Best-effort removal of the audio object uploaded for a failed sermon
 * create (TAB-34).
 *
 * The path arrives in the request body and this runs with the service role,
 * so it must be validated before deleting:
 * - it must sit under the authenticated user's own prefix
 *   (generate-upload-url issues `${user.id}/${randomUUID()}.${ext}`), so one
 *   user can never delete another user's audio
 * - it must not be referenced by any existing sermons row, so a forced
 *   duplicate-localId failure can't be used to delete the audio of an
 *   already-synced sermon
 */
async function cleanupOrphanAudioUpload({ supabase, audioFilePath, userId, logger }) {
  if (!audioFilePath) return false;

  const path = String(audioFilePath);
  if (path.includes('..') || !path.startsWith(`${userId}/`)) {
    logger.warn('Skipping orphan audio cleanup for path outside user prefix', {
      audioFilePath: path,
      userId
    });
    return false;
  }

  try {
    const { data: referencing, error: lookupError } = await supabase
      .from('sermons')
      .select('id')
      .eq('audio_file_path', path)
      .limit(1);

    if (lookupError) {
      logger.warn('Skipping orphan audio cleanup; reference lookup failed', {
        audioFilePath: path,
        error: lookupError.message
      });
      return false;
    }

    if (referencing && referencing.length > 0) {
      logger.warn('Skipping orphan audio cleanup; path is referenced by a sermon', {
        audioFilePath: path,
        sermonId: referencing[0].id
      });
      return false;
    }

    const { error: removeError } = await supabase
      .storage
      .from('sermon-audio')
      .remove([path]);

    if (removeError) {
      logger.warn('Failed to clean up orphan audio upload', {
        audioFilePath: path,
        error: removeError.message
      });
      return false;
    }

    logger.info('Cleaned up orphan audio upload', { audioFilePath: path });
    return true;
  } catch (cleanupError) {
    logger.warn('Error cleaning up orphan audio upload', {
      audioFilePath: path,
      error: cleanupError.message
    });
    return false;
  }
}

module.exports = { cleanupOrphanAudioUpload };

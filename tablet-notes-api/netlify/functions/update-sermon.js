const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');
const { isOwnedObjectPath, objectPathFromUrl } = require('./utils/audioObjectPath');
const {
  planStageStatusWrites,
  applyStageStatusWrites
} = require('./utils/sermonStatus');
const { reconcileSermonNotes } = require('./utils/reconcileSermonNotes');

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
      // updated_at + stage statuses come along for the TAB-90 staleness guard.
      .select('id, user_id, updated_at, transcription_status, summary_status')
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
    if (body.audioFileUrl !== undefined) {
      // Same ownership boundary as create-sermon (TAB-84): this value reaches
      // service-role storage calls downstream.
      const claimedUrlPath = body.audioFileUrl ? objectPathFromUrl(body.audioFileUrl) : null;
      if (body.audioFileUrl && !claimedUrlPath) {
        logger.security('unrecognized_audio_url', {
          userId: user.id,
          claimedUrl: String(body.audioFileUrl).slice(0, 120)
        });
        return createErrorResponse(new Error('Invalid audio URL'), 400);
      }
      if (claimedUrlPath && !isOwnedObjectPath(claimedUrlPath, user.id)) {
        logger.security('unauthorized_audio_url', {
          userId: user.id,
          claimedPath: claimedUrlPath.slice(0, 120)
        });
        return createErrorResponse(new Error('Access denied: audio URL does not belong to you'), 403);
      }
      updateData.audio_file_url = body.audioFileUrl;
    }
    if (body.audioFileSizeBytes !== undefined) updateData.audio_file_size_bytes = body.audioFileSizeBytes;
    // A client with dirty metadata pushes BOTH stage statuses, even when it was
    // only editing a title. If the server has since completed that stage,
    // applying them would undo a finished transcription or summary (TAB-90).
    // The title and every other field still apply — only the stale status is
    // refused, and it is refused outright rather than on a timestamp comparison
    // (see utils/sermonStatus.js for why the timestamp version did not work).
    const { writes: stageWrites, dropped: droppedStages } = planStageStatusWrites({
      incoming: { transcriptionStatus: body.transcriptionStatus, summaryStatus: body.summaryStatus },
      server: existingSermon
    });

    // Each accepted status is written on its own, conditional on the column
    // still not being complete, so a stage that finishes between the read above
    // and the write is not overwritten. Runs BEFORE the metadata update so that
    // update sees the final drop list and can stamp the row accordingly.
    const { dropped: raceDropped } = await applyStageStatusWrites({
      supabase,
      sermonId: body.remoteId,
      userId: user.id,
      writes: stageWrites,
      logger
    });
    droppedStages.push(...raceDropped);

    if (droppedStages.length > 0) {
      logger.info('Ignored a client stage status that would undo a completed stage', {
        remoteId: body.remoteId,
        columns: droppedStages,
        clientUpdatedAt: body.updatedAt,
        serverUpdatedAt: existingSermon.updated_at
      });
    }

    if (body.isArchived !== undefined) updateData.is_archived = body.isArchived;

    // Always update the timestamp.
    //
    // When a status was refused, the row must end up strictly NEWER than the
    // client's own timestamp. `SyncService.mergeRemoteSermon` only applies a
    // remote row whose updatedAt is strictly greater than the local one, so
    // echoing the client's timestamp back would leave that device unable to
    // ever import the `complete` this endpoint just protected.
    updateData.updated_at = droppedStages.length > 0
      ? new Date().toISOString()
      : (body.updatedAt || new Date().toISOString());

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

    // Child scopes are acknowledged individually, the same contract as
    // create-sermon (TAB-34): a scope that failed stays dirty on the client
    // and is re-pushed, instead of being acked by a blanket 2xx.
    const syncedScopes = { metadata: true, notes: true, transcript: true, summary: true };

    // Reconcile notes if provided. Never delete-before-insert (TAB-110): the
    // helper inserts/updates first and removes stale rows last, and reports
    // any failure so the scope is not acknowledged.
    if (body.notes && Array.isArray(body.notes)) {
      syncedScopes.notes = await reconcileSermonNotes({
        supabase,
        sermonId: body.remoteId,
        userId: user.id,
        notes: body.notes,
        logger
      });
    }

    // Update transcript if provided
    if (body.transcript && body.transcript.text) {
      logger.info('Updating transcript', {
        sermonId: body.remoteId,
        textLength: body.transcript.text?.length || 0,
        hasId: !!body.transcript.id
      });
      const transcriptData = {
        local_id: body.transcript.id,
        sermon_id: body.remoteId,
        user_id: user.id,
        text: body.transcript.text,
        segments: body.transcript.segments || null,
        status: body.transcript.status || 'complete'
      };

      const { data: upsertedTranscript, error: transcriptError } = await supabase
        .from('transcripts')
        .upsert(transcriptData, {
          onConflict: 'sermon_id'
        })
        .select();

      if (transcriptError) {
        syncedScopes.transcript = false;
        logger.error('Failed to update transcript', {
          sermonId: body.remoteId,
          error: transcriptError.message,
          code: transcriptError.code,
          details: transcriptError.details
        });
      } else {
        logger.info('Successfully updated transcript', {
          sermonId: body.remoteId,
          transcriptId: upsertedTranscript?.[0]?.id
        });
      }
    } else {
      logger.info('No transcript to update', {
        sermonId: body.remoteId,
        hasTranscript: !!body.transcript,
        hasText: !!(body.transcript && body.transcript.text)
      });
    }

    // Update summary if provided
    if (body.summary && body.summary.text) {
      logger.info('Updating summary', {
        sermonId: body.remoteId,
        textLength: body.summary.text?.length || 0,
        title: body.summary.title || '(no title)',
        hasId: !!body.summary.id
      });
      const summaryData = {
        local_id: body.summary.id,
        sermon_id: body.remoteId,
        user_id: user.id,
        title: body.summary.title || '',
        text: body.summary.text,
        type: body.summary.type || 'devotional',
        status: body.summary.status || 'complete'
      };

      const { data: upsertedSummary, error: summaryError } = await supabase
        .from('summaries')
        .upsert(summaryData, {
          onConflict: 'sermon_id'
        })
        .select();

      if (summaryError) {
        syncedScopes.summary = false;
        logger.error('Failed to update summary', {
          sermonId: body.remoteId,
          error: summaryError.message,
          code: summaryError.code,
          details: summaryError.details
        });
      } else {
        logger.info('Successfully updated summary', {
          sermonId: body.remoteId,
          summaryId: upsertedSummary?.[0]?.id
        });
      }
    } else {
      logger.info('No summary to update', {
        sermonId: body.remoteId,
        hasSummary: !!body.summary,
        hasText: !!(body.summary && body.summary.text)
      });
    }

    if (!syncedScopes.notes || !syncedScopes.transcript || !syncedScopes.summary) {
      logger.warn('Sermon updated with partial child writes', {
        userId: user.id,
        sermonId: sermon.id,
        syncedScopes
      });
    } else {
      logger.info('Sermon updated successfully', {
        userId: user.id,
        sermonId: sermon.id
      });
    }

    return createSuccessResponse({
      id: sermon.id,
      updatedAt: sermon.updated_at,
      syncedScopes
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

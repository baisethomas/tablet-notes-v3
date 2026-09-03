/**
 * Brings a sermon's cloud notes in line with the client's snapshot WITHOUT
 * ever deleting before the replacement is safely stored (TAB-110).
 *
 * The previous update-sermon implementation deleted every note for the sermon
 * and then inserted the payload. A failed insert (bad row, transient DB error)
 * left the sermon with zero notes in the cloud while the endpoint still
 * returned 2xx, so the client acknowledged the scope and the next pull deleted
 * the local copies too. This helper:
 *
 *   1. reads the existing rows,
 *   2. inserts notes the cloud doesn't have yet,
 *   3. updates notes whose text/timestamp changed (keeping their remote ids),
 *   4. only then deletes rows the client no longer has,
 *
 * and reports `false` on ANY failure so the caller returns
 * `syncedScopes.notes = false` and the client keeps the scope dirty.
 *
 * Every step is scoped by `user_id` as well as `sermon_id`; ownership of the
 * sermon itself is checked by the caller.
 *
 * @returns {Promise<boolean>} true when the cloud now matches the payload.
 */
async function reconcileSermonNotes({ supabase, sermonId, userId, notes, logger }) {
  const desired = notes.map(note => ({
    local_id: note.id,
    sermon_id: sermonId,
    user_id: userId,
    text: note.text,
    // notes.timestamp is an integer column; the client sends fractional
    // seconds and an unrounded value fails the whole insert with 22P02.
    timestamp: Math.round(note.timestamp) || 0
  }));

  const { data: existing, error: readError } = await supabase
    .from('notes')
    .select('id, local_id, text, timestamp')
    .eq('sermon_id', sermonId)
    .eq('user_id', userId);

  if (readError) {
    logger.error('Failed to read existing notes', {
      sermonId,
      error: readError.message,
      code: readError.code
    });
    return false;
  }

  const existingByLocalId = new Map((existing || []).map(row => [row.local_id, row]));
  const desiredLocalIds = new Set(desired.map(row => row.local_id));

  const toInsert = desired.filter(row => !existingByLocalId.has(row.local_id));
  const toUpdate = desired
    .map(row => ({ row, current: existingByLocalId.get(row.local_id) }))
    .filter(({ row, current }) => current && (current.text !== row.text || current.timestamp !== row.timestamp));
  const toDelete = (existing || []).filter(row => !desiredLocalIds.has(row.local_id));

  logger.info('Reconciling notes', {
    sermonId,
    existing: existingByLocalId.size,
    insert: toInsert.length,
    update: toUpdate.length,
    delete: toDelete.length
  });

  if (toInsert.length > 0) {
    const { error: insertError } = await supabase
      .from('notes')
      .insert(toInsert)
      .select();

    if (insertError) {
      logger.error('Failed to insert notes; existing notes left untouched', {
        sermonId,
        count: toInsert.length,
        error: insertError.message,
        code: insertError.code,
        details: insertError.details
      });
      return false;
    }
  }

  for (const { row, current } of toUpdate) {
    const { error: updateError } = await supabase
      .from('notes')
      .update({ text: row.text, timestamp: row.timestamp })
      .eq('id', current.id)
      .eq('user_id', userId);

    if (updateError) {
      logger.error('Failed to update note', {
        sermonId,
        noteId: current.id,
        error: updateError.message,
        code: updateError.code
      });
      return false;
    }
  }

  if (toDelete.length > 0) {
    const { error: deleteError } = await supabase
      .from('notes')
      .delete()
      .eq('sermon_id', sermonId)
      .eq('user_id', userId)
      .in('id', toDelete.map(row => row.id));

    if (deleteError) {
      // Inserts/updates above already landed; only the removal is retried.
      logger.error('Failed to delete stale notes', {
        sermonId,
        count: toDelete.length,
        error: deleteError.message,
        code: deleteError.code
      });
      return false;
    }
  }

  return true;
}

module.exports = { reconcileSermonNotes };

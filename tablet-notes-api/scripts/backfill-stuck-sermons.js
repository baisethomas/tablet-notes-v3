#!/usr/bin/env node
/**
 * TAB-39: normalize production sermons stuck in non-terminal processing
 * states so client-side recovery (TAB-22/23 retry services) can re-queue
 * them on the next sync.
 *
 * What it changes (rows older than the cutoff only):
 *   1. transcription_status 'processing'           -> 'failed'
 *      (TranscriptionRetryService retries 'failed'/'pending')
 *   2. summary_status 'processing' when
 *      transcription_status is 'complete'          -> 'pending'
 *      (SummaryRetryService re-queues 'pending')
 *
 * Both updates bump updated_at so the pull phase treats the remote row as
 * newer and propagates the retryable status to every device.
 *
 * What it deliberately does NOT touch:
 *   - transcription 'failed' or 'pending' rows — already client-retryable
 *   - anything newer than the cutoff — might be genuinely in flight
 *
 * Usage:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     node scripts/backfill-stuck-sermons.js                 # dry run
 *     node scripts/backfill-stuck-sermons.js --execute       # apply
 *     node scripts/backfill-stuck-sermons.js --older-than-hours=48
 */
const { createClient } = require('@supabase/supabase-js');

function parseArgs(argv) {
  const args = { execute: false, olderThanHours: 24 };
  for (const arg of argv.slice(2)) {
    if (arg === '--execute') {
      args.execute = true;
    } else if (arg.startsWith('--older-than-hours=')) {
      const hours = Number(arg.split('=')[1]);
      if (!Number.isFinite(hours) || hours < 1) {
        throw new Error(`Invalid --older-than-hours value: ${arg}`);
      }
      args.olderThanHours = hours;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return args;
}

async function printStatusBreakdown(supabase, label) {
  const { data, error } = await supabase
    .from('sermons')
    .select('transcription_status, summary_status');
  if (error) throw new Error(`Failed to fetch status breakdown: ${error.message}`);

  const counts = new Map();
  for (const row of data) {
    const key = `transcription=${row.transcription_status ?? 'NULL'} summary=${row.summary_status ?? 'NULL'}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  }

  console.log(`\n${label} (${data.length} sermons total):`);
  for (const [key, count] of [...counts.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  ${key} count=${count}`);
  }
}

async function fetchBucket(supabase, description, filters, cutoffIso) {
  let query = supabase
    .from('sermons')
    .select('id, user_id, title, transcription_status, summary_status, updated_at')
    .lt('updated_at', cutoffIso);
  for (const [column, value] of Object.entries(filters)) {
    query = query.eq(column, value);
  }
  const { data, error } = await query;
  if (error) throw new Error(`Failed to fetch ${description}: ${error.message}`);
  return data;
}

async function applyUpdate(supabase, ids, patch, guard, cutoffIso) {
  // Chunk to stay well under URL length limits for the id list.
  const chunkSize = 50;
  let updated = 0;
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    let query = supabase
      .from('sermons')
      .update({ ...patch, updated_at: new Date().toISOString() })
      .in('id', chunk)
      // Re-check the expected status + cutoff at write time so a row that
      // changed between the dry-run selection and now is left untouched.
      .lt('updated_at', cutoffIso);
    for (const [column, value] of Object.entries(guard)) {
      query = query.eq(column, value);
    }
    const { data, error } = await query.select('id');
    if (error) throw new Error(`Update failed for chunk starting at ${i}: ${error.message}`);
    updated += data.length;
  }
  return updated;
}

async function main() {
  const args = parseArgs(process.argv);

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !supabaseKey) {
    console.error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
    process.exit(1);
  }

  const supabase = createClient(supabaseUrl, supabaseKey);
  const cutoffIso = new Date(Date.now() - args.olderThanHours * 3600 * 1000).toISOString();

  console.log(`Mode: ${args.execute ? 'EXECUTE' : 'DRY RUN (pass --execute to apply)'}`);
  console.log(`Cutoff: rows not updated since ${cutoffIso} (${args.olderThanHours}h)`);

  await printStatusBreakdown(supabase, 'Status breakdown BEFORE');

  const stuckTranscription = await fetchBucket(
    supabase,
    'stuck transcription rows',
    { transcription_status: 'processing' },
    cutoffIso
  );
  const stuckSummaries = await fetchBucket(
    supabase,
    'stuck summary rows',
    { transcription_status: 'complete', summary_status: 'processing' },
    cutoffIso
  );

  console.log(`\nBucket 1 — transcription 'processing' -> 'failed': ${stuckTranscription.length} rows`);
  for (const row of stuckTranscription) {
    console.log(`  ${row.id} user=${row.user_id} updated=${row.updated_at} "${(row.title || '').slice(0, 40)}"`);
  }

  console.log(`\nBucket 2 — summary 'processing' -> 'pending' (transcription complete): ${stuckSummaries.length} rows`);
  for (const row of stuckSummaries) {
    console.log(`  ${row.id} user=${row.user_id} updated=${row.updated_at} "${(row.title || '').slice(0, 40)}"`);
  }

  if (!args.execute) {
    console.log('\nDry run complete. No changes made.');
    return;
  }

  if (stuckTranscription.length > 0) {
    // Only normalize transcription. Once the client re-transcribes and the
    // row reaches 'complete', SummaryRetryService re-queues the summary
    // (it acts on summary status processing/pending) — so we never rewrite
    // summary_status here and can't clobber an unrelated summary state.
    const updated = await applyUpdate(
      supabase,
      stuckTranscription.map(r => r.id),
      { transcription_status: 'failed' },
      { transcription_status: 'processing' },
      cutoffIso
    );
    console.log(`\nUpdated ${updated} stuck transcription rows` +
      (updated < stuckTranscription.length
        ? ` (${stuckTranscription.length - updated} skipped — changed since selection)`
        : ''));
  }

  if (stuckSummaries.length > 0) {
    const updated = await applyUpdate(
      supabase,
      stuckSummaries.map(r => r.id),
      { summary_status: 'pending' },
      { transcription_status: 'complete', summary_status: 'processing' },
      cutoffIso
    );
    console.log(`Updated ${updated} stuck summary rows` +
      (updated < stuckSummaries.length
        ? ` (${stuckSummaries.length - updated} skipped — changed since selection)`
        : ''));
  }

  await printStatusBreakdown(supabase, 'Status breakdown AFTER');
}

main().catch(error => {
  console.error(`Backfill failed: ${error.message}`);
  process.exit(1);
});

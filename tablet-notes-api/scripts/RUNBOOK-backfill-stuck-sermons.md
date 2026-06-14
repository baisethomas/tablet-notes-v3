# Runbook: backfill stuck production sermons (TAB-39)

## Background

As of 2026-06-12, production has 364 sermons, 61 of them stuck in
non-terminal states (matching the count in TAB-39):

| transcription | summary    | count | recovery path                            |
|---------------|------------|------:|------------------------------------------|
| failed        | pending    |    30 | already client-retryable — untouched      |
| complete      | processing |    16 | script → summary `pending`                |
| processing    | pending    |     7 | script → transcription `failed`           |
| pending       | pending    |     6 | already client-retryable — untouched      |
| processing    | processing |     2 | script → transcription `failed`           |

The script normalizes stuck `processing` states into the states the
client retry services act on (`TranscriptionRetryService` retries
`failed`/`pending`; `SummaryRetryService` re-queues `pending`), and bumps
`updated_at` so the next sync pull propagates the retryable status to
devices. Actual re-transcription/re-summarization happens client-side on
devices running the TAB-22/23 app build — recovery therefore depends on
users opening the updated app.

## Prerequisites

- [ ] Phase 1 + Phase 2 API deployed to Netlify prod (done through TAB-37)
- [ ] TAB-37 rate limiting deployed (cost protection before re-queued AI runs)
- [ ] App build containing TAB-22/23 retry fixes live in the App Store
- [ ] This runbook reviewed by the owner

## Execute

```bash
cd tablet-notes-api

# 1. Dry run — prints before-breakdown and every row that would change
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
node scripts/backfill-stuck-sermons.js

# 2. Review the dry-run output. Row counts should match the table above
#    (minus anything organically recovered since).

# 3. Apply
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
node scripts/backfill-stuck-sermons.js --execute
```

Use `--older-than-hours=N` (default 24) to widen/narrow the cutoff. Rows
updated more recently than the cutoff are never touched — they may be
genuinely in flight.

## Verify

Immediately after execution the script prints the AFTER breakdown. Expect:
- `transcription=processing` count → 0 (older than cutoff)
- `summary=processing` with complete transcription → 0

Over the following days, re-run the breakdown (dry run does this without
changing anything) and confirm stuck counts trend toward zero as users
open the updated app:

```sql
SELECT transcription_status, summary_status, count(*)
FROM sermons GROUP BY 1, 2 ORDER BY 3 DESC;
```

## Rollback

The script only rewrites status strings on already-stuck rows; no data is
deleted. If needed, statuses can be set back with a manual UPDATE, but
there is no scenario where the previous stuck `processing` state is more
correct than `failed`/`pending`.

## Known limitations

- Sermons whose owners never open the app again stay in `failed`/`pending`
  — server-side re-processing (invoking transcribe/summarize with user
  context) is out of scope for this pass.
- Free-tier users don't sync, so cloud-status normalization only reaches
  their devices if they upgrade; their local recovery still works via the
  TAB-22 on-device sweep.

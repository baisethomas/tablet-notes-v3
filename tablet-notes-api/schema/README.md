# Prod schema — documentation of record

**These files mirror the live Supabase production schema. They are documentation,
not migrations. Never run them against prod** — migrations remain owner-run via
the Supabase SQL editor (CLAUDE.md §8). Their purpose is to make the schema
reviewable, diffable, and recreatable in a fresh environment; before this
directory existed, the running database was the schema's only source of truth
(TAB-101 / TAB-72 follow-up).

Captured 2026-08-31 from project `ubghnmenxbhhlpxvypea` via read-only catalog
queries (Supabase Management API `database/query`, SELECTs only).

## Scope

| File | Table | Owner |
|---|---|---|
| `processing_jobs.sql` | `public.processing_jobs` | Durable pipeline (TAB-72): `jobs.js`, `assemblyai-webhook.js`, `jobs-reaper-background.js` |
| `profiles.sql` | `public.profiles` | Auth + subscriptions: `verify-purchase.js`, `SupabaseAuthService` |

Other tables (`sermons`, `notes`, `transcripts`, `summaries`) predate this
directory and are not yet captured — extend the same way if needed.

## Verifying against live prod

Re-run the capture queries and diff against these files:

```sql
-- Columns
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = '<table>'
order by ordinal_position;

-- Constraints
select conname, pg_get_constraintdef(oid)
from pg_constraint where conrelid = 'public.<table>'::regclass;

-- Indexes
select indexname, indexdef from pg_indexes
where schemaname = 'public' and tablename = '<table>';

-- RLS + policies
select policyname, cmd, roles::text, qual, with_check
from pg_policies where schemaname = 'public' and tablename = '<table>';
```

## Known warts (documented as found, deliberately not "fixed" here)

The `profiles` policy set has accumulated near-duplicate policies across
several generations of manual SQL-editor work, including two that deserve
scrutiny (tracked separately — see TAB-108):

- `Allow profile writes` — `INSERT` with `WITH CHECK (true)`: any request,
  including anon-key, may insert a profile row for any id that exists in
  `auth.users`.
- `Allow profile reads with restrictions` — `SELECT` allows reading **any**
  profile for 5 minutes after its creation, not just your own.

A documentation-of-record file records what is, warts included; policy cleanup
is a behavior change and gets its own issue and owner-run migration.

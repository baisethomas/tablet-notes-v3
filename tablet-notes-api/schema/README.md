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

-- RLS + policies (pg_policies returns rows even when RLS is DISABLED —
-- check relrowsecurity too, or a silently-disabled RLS passes the diff)
select relrowsecurity from pg_class where oid = 'public.<table>'::regclass;
select policyname, cmd, roles::text, qual, with_check
from pg_policies where schemaname = 'public' and tablename = '<table>';

-- Triggers + their functions
select tgname, pg_get_triggerdef(oid)
from pg_trigger where tgrelid = 'public.<table>'::regclass and not tgisinternal;
select pg_get_functiondef('touch_processing_jobs_updated_at()'::regprocedure);
```

## Divergence from committed migrations

`supabase/migrations/20260807170000_add_processing_jobs_and_profiles.sql`
(repo root) declares a `profiles` definition that does NOT match live prod:
`subscription_status text not null default 'inactive'` and
`id … references auth.users(id) on delete cascade`. Prod actually has the
column nullable with default `'active'` and the FK with **no** delete action.
The migration used `create table if not exists` / `add column if not exists`,
so against the already-existing prod table those stricter clauses were silent
no-ops — its profiles DDL describes what a *fresh* database would get, not
what prod is. **This directory is authoritative for prod's current shape**;
reconciling the two (and deciding which defaults are intended) is part of the
TAB-108 cleanup.

## Known warts — do NOT bootstrap an environment from these files

The `profiles` policy set has accumulated near-duplicate policies across
several generations of manual SQL-editor work. Two are genuine security
findings, not hygiene (tracked as TAB-108; permissive policies OR together,
so the stricter duplicates are decorative):

- `Allow profile writes` — `INSERT` with `WITH CHECK (true)`: any request,
  anon-key included, may insert a profile row **with arbitrary column
  values** for any id in `auth.users`. Because `getSubscriptionState`
  derives the paid tier from `subscription_status = 'active'`, a user who
  signs up and inserts their own row with
  `subscription_tier='premium', subscription_status='active'` before the app
  does self-provisions premium entitlements — a privilege-escalation path,
  not a style issue.
- `Allow profile reads with restrictions` — `SELECT` allows **any** request
  to read **any** profile (email, name, subscription metadata) for 5 minutes
  after that profile's creation: a PII-exposure window for anyone polling
  with the anon key.

These files reproduce prod's state so it is reviewable — that is the
opposite of a recommendation. The two dangerous policies are preserved as
verbatim text inside comment blocks in `profiles.sql`, so an accidental
apply cannot recreate them (a policy diff against prod will therefore show
them present in prod and commented here — expected until TAB-108 removes
them from prod). Policy changes are owner-run migrations.

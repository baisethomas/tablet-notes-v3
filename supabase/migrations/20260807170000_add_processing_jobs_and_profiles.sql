-- TAB-72: Server-side processing jobs (processing_jobs) + committed profiles schema
--
-- Problem: the AssemblyAI job id lives only in the phone's memory. transcribe.js
-- submits the job and returns the provider id in the HTTP response; it is never
-- written to Postgres. If the app is killed, backgrounded past its polling
-- budget, or simply loses the process, the paid transcription is unreachable
-- forever and nothing server-side can reconcile it. Completion is detected by
-- foreground-only client polling (~200 authenticated round trips for a 90-minute
-- sermon), so "lock the phone after church" = stalled transcription.
--
-- This migration adds the durable job record that makes server-side
-- orchestration possible: AssemblyAI webhooks write results straight to
-- Postgres, Supabase Realtime pushes them to the device, and a scheduled reaper
-- retries stale jobs. It also finally commits the `profiles` schema, which is
-- read by subscriptionTier.js and written by verify-purchase.js but has never
-- had a definition in this repo.
--
-- Verified before applying (2026-08-07):
--   * `profiles` exists in prod and is read on every summarize/live-token call
--     (utils/subscriptionTier.js reads subscription_tier/status/expiry); this
--     migration is written to be a no-op against the live table via
--     `create table if not exists` + per-column `add column if not exists`.
--   * `sermons.local_id` is the client-generated UUID the app keys sermons by
--     (create-sermon.js inserts it; UNIQUE(user_id, local_id) already enforced),
--     so processing_jobs references sermons(id) and also carries sermon_local_id
--     for the client to match rows without an extra round trip.
--   * No table named processing_jobs exists yet.
--
-- Ownership model: rows are written ONLY by the service role (the /jobs
-- endpoint, the AssemblyAI webhook, and the reaper). Clients get SELECT on
-- their own rows and nothing else — that is exactly what Realtime needs to
-- stream updates, and it keeps job state un-forgeable from the client
-- (CLAUDE.md §6: never trust client-claimed state).

-- ---------------------------------------------------------------------------
-- profiles (committed definition; matches live prod)
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text,
    subscription_tier text not null default 'free',
    subscription_status text not null default 'inactive',
    subscription_expiry timestamptz,
    subscription_product_id text,
    subscription_original_transaction_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Additive guards so this is safe against the live table, whatever it already has.
alter table public.profiles add column if not exists subscription_tier text not null default 'free';
alter table public.profiles add column if not exists subscription_status text not null default 'inactive';
alter table public.profiles add column if not exists subscription_expiry timestamptz;
alter table public.profiles add column if not exists subscription_product_id text;
alter table public.profiles add column if not exists subscription_original_transaction_id text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

alter table public.profiles enable row level security;

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
    on public.profiles for select
    using (auth.uid() = id);

-- No client INSERT/UPDATE policy: entitlements are written server-side only,
-- from the verified StoreKit payload (verify-purchase.js). A request body
-- claiming a tier is an attack surface, not a fact.

-- ---------------------------------------------------------------------------
-- processing_jobs
-- ---------------------------------------------------------------------------

create table if not exists public.processing_jobs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    sermon_id uuid not null references public.sermons(id) on delete cascade,
    -- The client's local sermon UUID, so the device can match a Realtime row to
    -- its local SwiftData sermon without a second lookup.
    sermon_local_id uuid not null,

    kind text not null check (kind in ('transcription', 'summary')),
    status text not null default 'queued'
        check (status in ('queued', 'submitted', 'running', 'done', 'failed', 'dead')),

    -- AssemblyAI transcript id (transcription jobs). This is the field whose
    -- absence caused orphaned, unrecoverable paid jobs.
    provider_job_id text,
    -- Storage path of the audio, so the reaper can resubmit without the client.
    audio_file_path text,

    attempts integer not null default 0,
    max_attempts integer not null default 5,
    last_error text,

    -- One live job per (sermon, kind). A double-tap, a client retry after a lost
    -- response, or a reaper resubmit all collapse onto the same row instead of
    -- billing a second AssemblyAI transcription.
    idempotency_key text not null unique,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- When the reaper may next touch this job (exponential backoff).
    next_attempt_at timestamptz,
    -- Set when the job left the queue for a provider; drives stale detection.
    submitted_at timestamptz,
    completed_at timestamptz
);

comment on table public.processing_jobs is
    'Durable server-side record of transcription/summary work (TAB-72). Written by the service role only; clients read their own rows via Realtime.';
comment on column public.processing_jobs.idempotency_key is
    'sermon_id + kind. Unique, so retries never create a second billable provider job.';

create index if not exists idx_processing_jobs_user_id
    on public.processing_jobs (user_id);
create index if not exists idx_processing_jobs_sermon_id
    on public.processing_jobs (sermon_id);
-- The reaper's sweep: unfinished jobs whose backoff has elapsed.
create index if not exists idx_processing_jobs_status_next_attempt
    on public.processing_jobs (status, next_attempt_at)
    where status in ('queued', 'submitted', 'running');
-- Webhook lookup path: provider id -> job.
create index if not exists idx_processing_jobs_provider_job_id
    on public.processing_jobs (provider_job_id)
    where provider_job_id is not null;

alter table public.processing_jobs enable row level security;

drop policy if exists "Users can view own processing jobs" on public.processing_jobs;
create policy "Users can view own processing jobs"
    on public.processing_jobs for select
    using (auth.uid() = user_id);

-- Deliberately no INSERT/UPDATE/DELETE policy for authenticated users: all
-- writes go through the service role (POST /jobs, the AssemblyAI webhook, the
-- reaper). RLS-filtered SELECT is also what makes the Realtime subscription
-- safe — a device only ever receives its own job rows.

-- Keep updated_at honest without relying on every writer to remember it.
create or replace function public.touch_processing_jobs_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_processing_jobs_updated_at on public.processing_jobs;
create trigger trg_processing_jobs_updated_at
    before update on public.processing_jobs
    for each row execute function public.touch_processing_jobs_updated_at();

-- Realtime delivery for this table. Guarded: adding a table already in the
-- publication raises, and this migration must stay re-runnable.
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'processing_jobs'
    ) then
        alter publication supabase_realtime add table public.processing_jobs;
    end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Sync-support indexes flagged by the audit (docs/rewrite/01-consolidated-audit.md
-- S3-2): every RLS predicate filters on user_id, but only sermons had that index.
-- ---------------------------------------------------------------------------

create index if not exists idx_notes_user_id on public.notes (user_id);
create index if not exists idx_transcripts_user_id on public.transcripts (user_id);
create index if not exists idx_summaries_user_id on public.summaries (user_id);
-- Delta pull wants (user_id, updated_at); the existing idx_sermons_updated_at is
-- global and cannot serve `where user_id = ? and updated_at > ?`.
create index if not exists idx_sermons_user_updated_at
    on public.sermons (user_id, updated_at desc);

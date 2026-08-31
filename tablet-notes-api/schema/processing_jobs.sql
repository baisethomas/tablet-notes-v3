-- public.processing_jobs — durable processing pipeline job table (TAB-72).
--
-- DOCUMENTATION OF RECORD: mirrors prod (ubghnmenxbhhlpxvypea) as of
-- 2026-08-31. Do NOT run against prod; migrations are owner-run.
-- See schema/README.md for the verification queries.
--
-- One row per (sermon, kind) unit of server-side work. The idempotency key
-- (written by jobs.js as a deterministic function of sermon + kind) is what
-- makes job creation safe to retry: a duplicate POST /jobs upserts into the
-- same row instead of double-submitting to AssemblyAI. The reaper
-- (jobs-reaper-background.js, every 5 min) retries stalled jobs with backoff
-- up to max_attempts, then marks them dead.

create table public.processing_jobs (
    id               uuid        not null default gen_random_uuid(),
    user_id          uuid        not null,
    sermon_id        uuid        not null,
    sermon_local_id  uuid        not null,
    kind             text        not null,
    status           text        not null default 'queued',
    provider_job_id  text,
    audio_file_path  text,
    attempts         integer     not null default 0,
    max_attempts     integer     not null default 5,
    last_error       text,
    idempotency_key  text        not null,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    next_attempt_at  timestamptz,
    submitted_at     timestamptz,
    completed_at     timestamptz,

    constraint processing_jobs_pkey primary key (id),
    constraint processing_jobs_idempotency_key_key unique (idempotency_key),
    constraint processing_jobs_kind_check
        check (kind = any (array['transcription'::text, 'summary'::text])),
    constraint processing_jobs_status_check
        check (status = any (array['queued'::text, 'submitted'::text, 'running'::text,
                                   'done'::text, 'failed'::text, 'dead'::text])),
    constraint processing_jobs_sermon_id_fkey
        foreign key (sermon_id) references sermons (id) on delete cascade,
    constraint processing_jobs_user_id_fkey
        foreign key (user_id) references auth.users (id) on delete cascade
);

create index idx_processing_jobs_sermon_id
    on public.processing_jobs using btree (sermon_id);

create index idx_processing_jobs_user_id
    on public.processing_jobs using btree (user_id);

-- Partial: the reaper's scan — only non-terminal jobs are ever candidates.
create index idx_processing_jobs_status_next_attempt
    on public.processing_jobs using btree (status, next_attempt_at)
    where status = any (array['queued'::text, 'submitted'::text, 'running'::text]);

-- Partial: webhook lookup by the provider's id.
create index idx_processing_jobs_provider_job_id
    on public.processing_jobs using btree (provider_job_id)
    where provider_job_id is not null;

-- RLS: clients may only read their own jobs (Realtime subscription in
-- ProcessingObserver). All writes go through service-role functions.
alter table public.processing_jobs enable row level security;

create policy "Users can view own processing jobs"
    on public.processing_jobs for select
    using (auth.uid() = user_id);

-- updated_at is server-owned: every UPDATE re-stamps it.
create or replace function public.touch_processing_jobs_updated_at()
returns trigger
language plpgsql
as $function$
begin
    new.updated_at = now();
    return new;
end;
$function$;

create trigger trg_processing_jobs_updated_at
    before update on public.processing_jobs
    for each row execute function touch_processing_jobs_updated_at();

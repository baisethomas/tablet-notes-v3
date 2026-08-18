-- TAB-85: two new terminal values for the sermon stage columns.
--
--   no_speech         transcription succeeded; the recording contained no speech
--   failed_permanent  the pipeline used up its attempts and stopped trying
--
-- Whether this is needed at all is genuinely uncertain, and this migration is
-- written to be correct either way.
--
-- `processing_jobs.status` carries a CHECK (see 20260807170000), but `sermons`
-- predates this repo's migration history, so its live definition is not in the
-- tree. The archived schema (docs/archive/sql/SUPABASE_SCHEMA.sql) declares
--     transcription_status TEXT NOT NULL DEFAULT 'pending'
-- listing the allowed values in a *comment* rather than a constraint, which
-- suggests there is none — but that file has drifted from production before
-- (it says the default is 'pending'; PostgREST reports 'processing'), and
-- PostgREST cannot report CHECK constraints, so it could not be confirmed
-- from the outside.
--
-- So: widen a constraint if one exists, and add nothing if one does not.
-- Introducing a constraint where none existed would be a new way for a write to
-- fail closed in production, which is not a thing to do on a guess.
--
-- To see which case you are in:
--   select conname, pg_get_constraintdef(oid)
--   from pg_constraint
--   where conrelid = 'public.sermons'::regclass and contype = 'c';

do $$
declare
    existing record;
    widened boolean := false;
begin
    for existing in
        select conname
        from pg_constraint
        where conrelid = 'public.sermons'::regclass
          and contype = 'c'
          and pg_get_constraintdef(oid) ~ '(transcription_status|summary_status)'
    loop
        raise notice 'TAB-85: dropping stage-status constraint %', existing.conname;
        execute format('alter table public.sermons drop constraint %I', existing.conname);
        widened := true;
    end loop;

    if widened then
        alter table public.sermons
            add constraint sermons_transcription_status_check
            check (transcription_status in (
                'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
            ));

        alter table public.sermons
            add constraint sermons_summary_status_check
            check (summary_status in (
                'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
            ));

        raise notice 'TAB-85: stage-status constraints recreated with the terminal values';
    else
        raise notice 'TAB-85: no stage-status CHECK constraint found; nothing to widen';
    end if;
end $$;

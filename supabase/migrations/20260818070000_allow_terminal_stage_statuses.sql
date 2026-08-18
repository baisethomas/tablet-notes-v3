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
-- Constraints are selected by pg_constraint.conkey — the catalog's own record
-- of which columns a constraint covers — not by matching the column name in
-- its text. Only a constraint covering EXACTLY one stage column is replaced;
-- one that spans a stage column plus anything else enforces a rule this
-- migration does not know about, so it aborts with the definition in hand
-- rather than silently rewriting the constraint down to a value allow-list
-- (PR #52 review).
--
-- To see which case you are in:
--   select conname, pg_get_constraintdef(oid)
--   from pg_constraint
--   where conrelid = 'public.sermons'::regclass and contype = 'c';

do $$
declare
    tcol constant smallint := (
        select attnum from pg_attribute
        where attrelid = 'public.sermons'::regclass
          and attname = 'transcription_status' and not attisdropped
    );
    scol constant smallint := (
        select attnum from pg_attribute
        where attrelid = 'public.sermons'::regclass
          and attname = 'summary_status' and not attisdropped
    );
    existing record;
    widen_transcription boolean := false;
    widen_summary boolean := false;
begin
    for existing in
        select conname, conkey, pg_get_constraintdef(oid) as def
        from pg_constraint
        where conrelid = 'public.sermons'::regclass
          and contype = 'c'
          and (conkey @> array[tcol] or conkey @> array[scol])
    loop
        if existing.conkey <> array[tcol] and existing.conkey <> array[scol] then
            raise exception
                'TAB-85: constraint % covers more than a single stage column and may enforce '
                'a rule beyond a value allow-list; widen it by hand instead. Definition: %',
                existing.conname, existing.def;
        end if;

        raise notice 'TAB-85: dropping stage-status constraint % (%)', existing.conname, existing.def;
        execute format('alter table public.sermons drop constraint %I', existing.conname);

        if existing.conkey = array[tcol] then
            widen_transcription := true;
        else
            widen_summary := true;
        end if;
    end loop;

    -- Recreate only what was dropped: adding a constraint to a column that
    -- never had one is exactly the guess this migration refuses to make.
    if widen_transcription then
        alter table public.sermons
            add constraint sermons_transcription_status_check
            check (transcription_status in (
                'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
            ));
        raise notice 'TAB-85: transcription_status constraint recreated with the terminal values';
    end if;

    if widen_summary then
        alter table public.sermons
            add constraint sermons_summary_status_check
            check (summary_status in (
                'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
            ));
        raise notice 'TAB-85: summary_status constraint recreated with the terminal values';
    end if;

    if not widen_transcription and not widen_summary then
        raise notice 'TAB-85: no stage-status CHECK constraint found; nothing to widen';
    end if;
end $$;

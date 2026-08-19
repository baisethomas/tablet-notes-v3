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
-- from the outside. Production was later queried directly (PR #52 round 2):
-- sermons has zero CHECK constraints, so this is a no-op against the live
-- table. The code still has to be correct if one appears before apply.
--
-- So: widen a constraint if one exists, and add nothing if one does not.
-- Introducing a constraint where none existed would be a new way for a write to
-- fail closed in production, which is not a thing to do on a guess.
--
-- A constraint is replaced only when all of these are true (PR #52 review):
--   * pg_constraint.conkey says it covers exactly one stage column
--   * pg_get_constraintdef is a value allow-list (`IN` / `= ANY (ARRAY[...])`)
--   * every listed value is a known stage status
--   * that column has exactly one such CHECK
-- Anything else — a format check, `<> ''`, a cross-column rule, two CHECKs on
-- the same column, an unknown value — aborts with the definition in the error
-- and does not touch the table. `conkey` alone is not enough: it names the
-- columns, not the rule.
--
-- To see which case you are in:
--   select conname, pg_get_constraintdef(oid)
--   from pg_constraint
--   where conrelid = 'public.sermons'::regclass and contype = 'c';

do $tab85$
declare
    known constant text[] := array[
        'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
    ];
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
    t_cons text[] := '{}';
    s_cons text[] := '{}';
    colname text;
    vals text[];
    v text;
    skeleton text;
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

        colname := case
            when existing.conkey = array[tcol] then 'transcription_status'
            else 'summary_status'
        end;

        -- Quoted literals. Postgres prints `IN (...)` as
        --   CHECK ((col = ANY (ARRAY['pending'::text, ...])))
        -- and `<> ''` as CHECK ((col <> ''::text)).
        select coalesce(array_agg(m[1]), '{}')
          into vals
          from regexp_matches(existing.def, $re$'([^']*)'$re$, 'g') as m;

        -- Shape first: after stripping literals, casts, the column name, commas
        -- and whitespace, an allow-list collapses to one of two skeletons.
        -- `CHECK ((col <> ''::text))` becomes `check((<>))` and aborts here
        -- rather than being misread as an unknown status value of ''.
        skeleton := lower(regexp_replace(existing.def, '\s+', ' ', 'g'));
        skeleton := regexp_replace(skeleton, $re$'[^']*'$re$, '', 'g');
        skeleton := regexp_replace(skeleton, '::text', '', 'g');
        skeleton := regexp_replace(skeleton, '"', '', 'g');
        skeleton := regexp_replace(skeleton, colname, '', 'g');
        skeleton := regexp_replace(skeleton, '[,\s]', '', 'g');

        if skeleton not in (
            'check((=any(array[])))',
            'check(=any(array[]))',
            'check((in()))',
            'check(in())'
        ) then
            raise exception
                'TAB-85: constraint % on % is not a status allow-list; leaving it untouched. Definition: %',
                existing.conname, colname, existing.def;
        end if;

        if coalesce(cardinality(vals), 0) = 0 then
            raise exception
                'TAB-85: constraint % on % is an empty allow-list; leaving it untouched. Definition: %',
                existing.conname, colname, existing.def;
        end if;

        foreach v in array vals loop
            if not (v = any (known)) then
                raise exception
                    'TAB-85: constraint % on % allows % which is not a stage status; leaving it untouched. Definition: %',
                    existing.conname, colname, v, existing.def;
            end if;
        end loop;

        if existing.conkey = array[tcol] then
            t_cons := t_cons || existing.conname;
        else
            s_cons := s_cons || existing.conname;
        end if;
    end loop;

    -- Two CHECKs on the same column are two rules. Collapsing them into one
    -- allow-list would drop whichever was not the enum list.
    if cardinality(t_cons) > 1 then
        raise exception
            'TAB-85: transcription_status has % CHECK constraints (%); widen by hand rather than collapsing them',
            cardinality(t_cons), t_cons;
    end if;
    if cardinality(s_cons) > 1 then
        raise exception
            'TAB-85: summary_status has % CHECK constraints (%); widen by hand rather than collapsing them',
            cardinality(s_cons), s_cons;
    end if;

    -- Recreate only what was dropped: adding a constraint to a column that
    -- never had one is exactly the guess this migration refuses to make.
    if cardinality(t_cons) = 1 then
        raise notice 'TAB-85: dropping transcription_status allow-list %', t_cons[1];
        execute format('alter table public.sermons drop constraint %I', t_cons[1]);
        alter table public.sermons
            add constraint sermons_transcription_status_check
            check (transcription_status in (
                'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
            ));
        raise notice 'TAB-85: transcription_status constraint recreated with the terminal values';
    end if;

    if cardinality(s_cons) = 1 then
        raise notice 'TAB-85: dropping summary_status allow-list %', s_cons[1];
        execute format('alter table public.sermons drop constraint %I', s_cons[1]);
        alter table public.sermons
            add constraint sermons_summary_status_check
            check (summary_status in (
                'pending', 'processing', 'complete', 'failed', 'no_speech', 'failed_permanent'
            ));
        raise notice 'TAB-85: summary_status constraint recreated with the terminal values';
    end if;

    if cardinality(t_cons) = 0 and cardinality(s_cons) = 0 then
        raise notice 'TAB-85: no stage-status CHECK constraint found; nothing to widen';
    end if;
end $tab85$;

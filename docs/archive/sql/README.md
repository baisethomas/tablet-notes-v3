# Archived SQL — historical artifacts, NOT current schema

These files are point-in-time scripts from early development. They do not
describe the production database (several contradict each other and prod —
e.g. `notes.timestamp` is `INTEGER` in prod, `DOUBLE PRECISION` here), and
they must never be executed against any environment.

Current schema truth, per `TabletNotes/CLAUDE.md` §2/§8:
1. the live Supabase database (read-only queries), and
2. `supabase/migrations/` — the only place new schema changes land.

`DISABLE_BUCKET_RLS.sql` was deleted outright (TAB-70): it reversed the
storage RLS tightening in `supabase/migrations/20260610071500_*` and was one
accidental `psql -f` away from re-opening a cross-tenant leak.

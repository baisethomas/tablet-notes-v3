-- TAB-108: close the entitlement-forging hole on public.profiles, and clean
-- the accumulated RLS policy set.
--
-- THE HOLE (verified at the grants level, 2026-08-31): `anon` and
-- `authenticated` held table-level INSERT/UPDATE on profiles, and the own-row
-- RLS policies gate rows, not columns — so any signed-in user could PATCH
-- their own row to subscription_tier='premium', subscription_status='active'
-- and getSubscriptionState would read them as paid. Entitlements must be
-- writable only by the service role (verify-purchase.js, which derives them
-- from the verified StoreKit transaction — TAB-47).
--
-- ⚠ SEQUENCING — OWNER-RUN, AND ONLY AFTER THE TAB-108 CLIENT BUILD SHIPS.
-- Older clients write subscription_tier/subscription_expiry in
-- saveUserProfile's upsert; once this migration runs, those upserts FAIL
-- (42501 insufficient privilege on the column). The TAB-108 client change
-- removes those fields. With no public release yet the exposure is the
-- owner/test devices — update them, then run this.
--
-- Verification (before/after), read-only:
--   select grantee, privilege_type, count(*) cols
--   from information_schema.column_privileges
--   where table_schema='public' and table_name='profiles'
--     and column_name like 'subscription%' and grantee in ('anon','authenticated')
--   group by 1,2;                          -- BEFORE: rows exist. AFTER: none.
--   select policyname, cmd from pg_policies
--   where schemaname='public' and tablename='profiles' order by 1;
--                                          -- AFTER: exactly 4 policies.
-- After running: re-capture tablet-notes-api/schema/profiles.sql (its README
-- has the recipe) so the documentation of record follows prod.

begin;

-- ---------------------------------------------------------------------------
-- 1. Entitlement columns become service-role-only.
--
-- Postgres has no column-level REVOKE below a table-level GRANT, so: revoke
-- the table-level write privileges, then grant back per-column — identity and
-- usage-metric columns only. `anon` gets no write path at all (every client
-- profile write runs authenticated); service_role keeps its full table grant
-- and is untouched.
-- ---------------------------------------------------------------------------
revoke insert, update on public.profiles from anon, authenticated;

grant insert (
    id, email, name, profile_image_url, created_at, is_email_verified,
    monthly_recording_count, monthly_recording_minutes,
    current_storage_used_gb, monthly_export_count, last_usage_reset_date,
    updated_at
) on public.profiles to authenticated;

-- `id` and `created_at` appear in the UPDATE grant because the client's
-- profile save is a PostgREST UPSERT: its ON CONFLICT (id) DO UPDATE sets
-- EVERY payload column (id and created_at included), and the conflict-update
-- requires UPDATE privilege on each SET column — without them, a plain name
-- edit fails 42501 (caught in TAB-108 PR review). They are inert in
-- practice: profiles_update_policy's WITH CHECK (auth.uid() = id) means a
-- user can only "change" id to their own uid, and created_at drift is
-- limited to their own row.
grant update (
    id, email, name, profile_image_url, created_at, is_email_verified,
    monthly_recording_count, monthly_recording_minutes,
    current_storage_used_gb, monthly_export_count, last_usage_reset_date,
    updated_at
) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Drop the dangerous policies (see tablet-notes-api/schema/profiles.sql
--    for their verbatim text and analysis).
-- ---------------------------------------------------------------------------
-- Anon-key INSERT with WITH CHECK (true): arbitrary rows for any auth user id.
drop policy if exists "Allow profile writes" on public.profiles;
-- Any request may read ANY profile for 5 minutes after creation (PII window).
-- The signup flow reads its own profile with an authenticated session
-- (SupabaseAuthService.fetchUserProfile), which the own-row SELECT policy
-- covers; if signup breaks after this, this window was load-bearing — stop
-- and re-evaluate rather than re-adding it.
drop policy if exists "Allow profile reads with restrictions" on public.profiles;
-- auth.role()='authenticated' branch = cross-user INSERT for any signed-in caller.
drop policy if exists "Users can insert their own profile" on public.profiles;

-- ---------------------------------------------------------------------------
-- 3. Drop the redundant duplicates (permissive policies OR together; one
--    canonical policy per command is the whole contract).
-- ---------------------------------------------------------------------------
drop policy if exists "Users can view own profile" on public.profiles;
drop policy if exists "Users can view their own profile" on public.profiles;
drop policy if exists "Allow profile updates for own records" on public.profiles;  -- no WITH CHECK
drop policy if exists "Users can update their own profile" on public.profiles;

-- Remaining canonical set — all own-row:
--   profiles_select_policy            SELECT  using (auth.uid() = id)
--   profiles_insert_policy            INSERT  with check (auth.uid() = id)
--   profiles_update_policy            UPDATE  using/with check (auth.uid() = id)
--   "Users can delete their own profile" DELETE using (auth.uid() = id)

commit;

-- Post-run functional checks (owner):
--   1. Sign up a fresh account → profile row appears, app reaches Home.
--   2. Edit profile name → saves.
--   3. Sandbox purchase or restore → verify-purchase still writes the
--      subscription columns (service role, unaffected).
--   4. Attempt the forgery (PostgREST PATCH of own subscription_tier with a
--      user JWT) → must now fail with 42501.

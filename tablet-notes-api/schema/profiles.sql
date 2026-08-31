-- public.profiles — per-user profile + subscription state.
--
-- DOCUMENTATION OF RECORD: mirrors prod (ubghnmenxbhhlpxvypea) as of
-- 2026-08-31. Do NOT run against prod; migrations are owner-run.
-- See schema/README.md for the verification queries.
--
-- Subscription columns are written server-side by verify-purchase.js from the
-- verified StoreKit JWS (TAB-47); getSubscriptionState derives the paid tier
-- from subscription_status = 'active'. Note the schema default is
-- tier 'free' / status 'active' — a fresh row reads as an active free/trial
-- account, which is why "premium rows with no product_id" were trial defaults,
-- not purchases.

create table public.profiles (
    id                                  uuid    not null,
    email                               text,
    name                                text,
    profile_image_url                   text,
    created_at                          timestamptz default now(),
    is_email_verified                   boolean default false,
    subscription_tier                   text    default 'free',
    subscription_expiry                 timestamptz,
    subscription_status                 text    default 'active',
    monthly_recording_count             integer default 0,
    monthly_recording_minutes           integer default 0,
    current_storage_used_gb             double precision default 0.0,
    monthly_export_count                integer default 0,
    last_usage_reset_date               timestamptz default now(),
    subscription_product_id             text,
    subscription_purchase_date          timestamptz,
    subscription_renewal_date           timestamptz,
    subscription_original_transaction_id text,
    updated_at                          timestamptz default now(),

    constraint profiles_pkey primary key (id),
    -- No ON DELETE action: deleting an auth user with a profile row fails
    -- unless the profile is removed first (delete-account.js handles order).
    constraint profiles_id_fkey foreign key (id) references auth.users (id)
);

create index idx_profiles_email on public.profiles using btree (email);

-- RLS: enabled. Policy set cleaned by the TAB-108 migration
-- (20260831210000, applied to prod 2026-08-31) — the accumulated
-- near-duplicates and the three dangerous policies (anon-key WITH CHECK
-- (true) insert, the 5-minute read-any-profile window, and the cross-user
-- authenticated insert) were dropped. What remains is one canonical own-row
-- policy per command. History of the removed policies lives in that
-- migration file and in this file's git history.
alter table public.profiles enable row level security;

create policy "profiles_select_policy"
    on public.profiles for select
    using (auth.uid() = id);

create policy "profiles_insert_policy"
    on public.profiles for insert
    with check (auth.uid() = id);

create policy "profiles_update_policy"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

create policy "Users can delete their own profile"
    on public.profiles for delete
    using (auth.uid() = id);

-- Column privileges (TAB-108): RLS gates rows, not columns. Entitlement
-- columns are service-role-only — verify-purchase.js (service role) is the
-- sole writer, deriving them from the verified StoreKit transaction. anon
-- and authenticated hold NO write on any subscription_* column, so a
-- signed-in user cannot forge premium by writing their own row.
--
--   revoke insert, update on public.profiles from anon, authenticated;
--   grant insert (id, email, name, profile_image_url, created_at,
--                 is_email_verified, monthly_recording_count,
--                 monthly_recording_minutes, current_storage_used_gb,
--                 monthly_export_count, last_usage_reset_date, updated_at)
--     on public.profiles to authenticated;
--   grant update (id, email, name, profile_image_url, created_at,
--                 is_email_verified, monthly_recording_count,
--                 monthly_recording_minutes, current_storage_used_gb,
--                 monthly_export_count, last_usage_reset_date, updated_at)
--     on public.profiles to authenticated;
--
-- (anon retains SELECT for the auth flow but no write path.)

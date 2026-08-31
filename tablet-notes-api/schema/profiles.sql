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

-- RLS: enabled, with a policy set accumulated across several generations of
-- manual SQL-editor work. Reproduced verbatim in TEXT — near-duplicates
-- included — because this file records what prod is, not what it should be.
-- The two policies below that are commented out are preserved for review
-- but NOT executable — applying this file cannot recreate prod's ANON-key
-- paths (arbitrary-id inserts; the 5-minute PII read window). Be clear
-- about what remains, though: even without them, the own-row INSERT/UPDATE
-- policies plus unrestricted column grants mean an AUTHENTICATED user can
-- write their own subscription_* columns — in this file AND in prod today.
-- That is prod's actual (broken) entitlement model, reproduced faithfully;
-- the fix (service-role-only entitlement columns + client coordination) is
-- TAB-108, an owner-run migration. A policy diff against prod will show
-- the two commented policies present in prod — expected until TAB-108.
alter table public.profiles enable row level security;

-- SELECT (three near-duplicates + one permissive variant)
create policy "Users can view own profile"
    on public.profiles for select
    using (auth.uid() = id);

create policy "Users can view their own profile"
    on public.profiles for select
    using (auth.uid() = id);

create policy "profiles_select_policy"
    on public.profiles for select
    using (auth.uid() = id);

-- ⚠⚠ DANGEROUS POLICY — PRESERVED AS DOCUMENTATION, DELIBERATELY NOT
-- EXECUTABLE (Ternary round 2): any request may read ANY profile (email,
-- name, subscription metadata) for 5 minutes after that profile's creation.
-- This exists in prod today (TAB-108 tracks its removal); reproducing it
-- runnably would let an accidental apply create the PII-exposure window in
-- a new environment. Verbatim text, commented:
--
--   create policy "Allow profile reads with restrictions"
--       on public.profiles for select
--       using ((auth.uid() = id) or (created_at > (now() - interval '5 minutes')));

-- INSERT (three variants)
-- ⚠⚠ DANGEROUS POLICY — PRESERVED AS DOCUMENTATION, DELIBERATELY NOT
-- EXECUTABLE (Ternary round 2): WITH CHECK (true) lets any request, anon
-- key included, insert a profile row with arbitrary column values for any
-- id in auth.users — a premium self-provisioning path (entitlements derive
-- from subscription_status='active'). Exists in prod today (TAB-108 tracks
-- its removal); must not be re-creatable by an accidental apply. Verbatim
-- text, commented:
--
--   create policy "Allow profile writes"
--       on public.profiles for insert
--       with check (true);

create policy "Users can insert their own profile"
    on public.profiles for insert
    with check ((auth.uid() = id) or (auth.role() = 'authenticated'));

create policy "profiles_insert_policy"
    on public.profiles for insert
    with check (auth.uid() = id);

-- UPDATE (three near-duplicates; one lacks WITH CHECK)
create policy "Allow profile updates for own records"
    on public.profiles for update
    using (auth.uid() = id);

create policy "Users can update their own profile"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

create policy "profiles_update_policy"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- DELETE
create policy "Users can delete their own profile"
    on public.profiles for delete
    using (auth.uid() = id);

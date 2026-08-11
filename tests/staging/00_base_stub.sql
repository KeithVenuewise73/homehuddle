-- Local staging harness: reproduce the REAL pre-migration Supabase objects the
-- HomeHuddle migrations depend on (base tables + auth helper functions + roles),
-- so migrations 0001-0006 apply and run exactly as they would on Supabase.
-- Synthetic data only.

create extension if not exists pgcrypto;

-- Supabase roles referenced by GRANT/REVOKE in the migrations.
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;

create schema if not exists auth;

-- Test-session identity via GUCs (simulates a signed-in user / admin).
create or replace function public.current_person_id() returns uuid
  language sql stable as $$ select nullif(current_setting('test.person_id', true),'')::uuid $$;
create or replace function auth.uid() returns uuid
  language sql stable as $$ select public.current_person_id() $$;
create or replace function public.is_admin() returns boolean
  language sql stable as $$ select coalesce(current_setting('test.is_admin', true),'false') = 'true' $$;

-- ── Base tables (pre-migration columns, matching the live schema) ────────────
create table public.families (
  id uuid primary key default gen_random_uuid(),
  family_name text not null, email text not null, phone text not null,
  pin text not null, status text default 'trial', created_at timestamptz default now(),
  sms_consent boolean default false, workspace_id uuid
);
create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid, name text not null, role text default 'parent', phone text, email text,
  receives_sms boolean default true, receives_push boolean default true,
  can_add_events boolean default false, can_edit_events boolean default false,
  is_owner boolean default false, created_at timestamptz default now(),
  person_id uuid, sms_status text not null default 'none', workspace_id uuid
);
create table public.feeds (
  id uuid primary key default gen_random_uuid(),
  family_name text, email text, phone text, kid_name text not null, sport text,
  platform text not null, ical_url text not null, is_active boolean default true,
  created_at timestamptz default now(), updated_at timestamptz default now(),
  theme jsonb, pin text, status text default 'trial', team_name text,
  cancelled_at timestamptz, workspace_id uuid
);
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null, stripe_customer_id text, stripe_subscription_id text,
  stripe_price_id text, status text not null default 'incomplete',
  trial_end timestamptz, current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  workspace_id uuid
);
create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  email text not null, endpoint text not null, keys jsonb not null,
  user_agent text, created_at timestamptz default now(), family_id uuid, member_id uuid
);

-- Helper functions that RLS policies reference (realistic: derive from membership).
create or replace function public.current_family_ids(p_editable boolean default false)
  returns setof uuid language sql stable as $$
    select fm.family_id from public.family_members fm
    where fm.person_id = public.current_person_id()
$$;
create or replace function public.current_family_emails()
  returns setof text language sql stable as $$
    select f.email from public.families f
    join public.family_members fm on fm.family_id = f.id
    where fm.person_id = public.current_person_id()
$$;

grant usage on schema auth to anon, authenticated, service_role;

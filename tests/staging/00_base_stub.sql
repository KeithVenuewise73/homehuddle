-- Local staging harness base: reproduces the REAL pre-migration Supabase objects
-- the HomeHuddle migrations depend on, faithfully enough to enforce RLS with the
-- actual anon/authenticated roles (SET ROLE + request.jwt.claims), using the
-- PRODUCTION definitions of the helper functions:
--   current_person_id() → people.auth_user_id = auth.uid()
--   is_admin()          → admin_users.user_id  = auth.uid()
-- Synthetic data only.

create extension if not exists pgcrypto;

do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
grant anon, authenticated, service_role to postgres;   -- allow SET ROLE in tests

create schema if not exists auth;
-- Supabase-compatible auth.uid(): read sub from request.jwt.claims GUC.
create or replace function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub')::uuid
$$;

-- Identity tables referenced by the production helper functions.
create table public.people (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid, full_name text, created_at timestamptz default now()
);
create table public.admin_users ( user_id uuid primary key );

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

-- Base-table RLS mirrors production (own-family scope); the migrations add the
-- new tables' policies. Enable + policies for the base tables here.
alter table public.families        enable row level security;
alter table public.family_members  enable row level security;
alter table public.subscriptions   enable row level security;
alter table public.feeds           enable row level security;

-- ── Production helper functions (SECURITY DEFINER, real bodies) ──────────────
create or replace function public.current_person_id() returns uuid
  language sql stable security definer set search_path=public as $$
    select id from public.people where auth_user_id = auth.uid() limit 1;
  $$;
create or replace function public.current_family_ids(p_editable boolean default false)
  returns setof uuid language sql stable security definer set search_path=public as $$
    select fm.family_id from public.family_members fm
    where fm.person_id = public.current_person_id();
  $$;
create or replace function public.current_family_emails()
  returns setof text language sql stable security definer set search_path=public as $$
    select f.email from public.families f
    join public.family_members fm on fm.family_id=f.id
    where fm.person_id = public.current_person_id();
  $$;
create or replace function public.is_admin() returns boolean
  language sql stable security definer set search_path=public as $$
    select exists (select 1 from public.admin_users where user_id = auth.uid());
  $$;

-- Base-table policies (own-family for authenticated; no anon read of PII).
create policy fam_sel   on public.families       for select to authenticated using (id in (select current_family_ids(false)));
create policy fam_adm   on public.families       for select to authenticated using (public.is_admin());
create policy fmem_sel  on public.family_members for select to authenticated using (family_id in (select current_family_ids(false)));
create policy sub_sel   on public.subscriptions  for select to authenticated using (family_id in (select current_family_ids(false)));
create policy sub_svc   on public.subscriptions  for all to service_role using (true) with check (true);
create policy feed_sel  on public.feeds          for select to authenticated using (email in (select current_family_emails()));

-- Supabase-style grants so RLS (not missing privileges) is the deciding factor.
grant usage on schema public, auth to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
grant select on all tables in schema public to anon;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated, service_role;
alter default privileges in schema public grant select on tables to anon;
grant execute on all functions in schema public to anon, authenticated, service_role;

-- Test helper: "log in" as the auth user behind a person (sets JWT claims).
create or replace function public.tst_login(p_auth_uid uuid) returns void
  language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', p_auth_uid)::text, false); $$;
create or replace function public.tst_logout() returns void
  language sql as $$ select set_config('request.jwt.claims', '', false); $$;

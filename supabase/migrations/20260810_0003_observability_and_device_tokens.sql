-- ============================================================================
-- 0003 · Observability (client_errors) + APNs device tokens  (ADDITIVE)
-- ----------------------------------------------------------------------------
-- Phase 11 (error visibility) + Phase 9 (native push). Both additive.
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

-- ── client_errors: minimum viable launch telemetry ──────────────────────────
create table if not exists public.client_errors (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  kind         text,            -- error | billing | feed_sync | push
  message      text,
  context      text,
  stack        text,
  platform     text,            -- web | ios | android
  path         text,
  app_version  text,
  ua           text,
  family_id    uuid
);
create index if not exists client_errors_created_idx on public.client_errors (created_at desc);
create index if not exists client_errors_kind_idx    on public.client_errors (kind, created_at desc);

alter table public.client_errors enable row level security;

-- Anyone may INSERT a bounded error record (same posture as existing intake
-- tables), but message length is capped to blunt spam/abuse.
drop policy if exists client_errors_insert on public.client_errors;
create policy client_errors_insert on public.client_errors
  for insert to anon, authenticated
  with check (char_length(coalesce(message,'')) <= 2000
              and char_length(coalesce(stack,'')) <= 4000);

-- Only admins may READ telemetry (drives the admin dashboard failure panels).
drop policy if exists client_errors_admin_select on public.client_errors;
create policy client_errors_admin_select on public.client_errors
  for select to authenticated
  using (public.is_admin());

drop policy if exists client_errors_service_all on public.client_errors;
create policy client_errors_service_all on public.client_errors
  for all to service_role using (true) with check (true);

-- ── device_tokens: native APNs/FCM tokens (web push stays in push_subscriptions) ─
create table if not exists public.device_tokens (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid references public.families(id) on delete cascade,
  member_id  uuid references public.family_members(id) on delete set null,
  platform   text not null check (platform in ('ios','android')),
  token      text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_family_idx on public.device_tokens (family_id);

alter table public.device_tokens enable row level security;

-- Authenticated users manage tokens for their OWN family only.
drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
  for select to authenticated
  using (family_id in (select current_family_ids(false)));

drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own on public.device_tokens
  for insert to authenticated
  with check (family_id in (select current_family_ids(false)));

drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own on public.device_tokens
  for update to authenticated
  using (family_id in (select current_family_ids(false)))
  with check (family_id in (select current_family_ids(false)));

drop policy if exists device_tokens_service_all on public.device_tokens;
create policy device_tokens_service_all on public.device_tokens
  for all to service_role using (true) with check (true);

commit;

-- ROLLBACK (reference):
--   drop table if exists public.device_tokens;
--   drop table if exists public.client_errors;

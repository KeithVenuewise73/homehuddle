-- ============================================================================
-- 0002 · Founding Family — first-100 slot enforcement  (SERVER-SIDE, race-safe)
-- ----------------------------------------------------------------------------
-- CEO-locked rule: first 100 QUALIFYING PAID HomeHuddle families get $4.99/mo
-- (Standard is $9.99/mo), grandfathered while continuously active. Founder
-- status is granted SERVER-SIDE at first successful payment (by the Stripe /
-- RevenueCat webhooks running as service_role) — never by client logic.
--
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

-- Cap configuration (data, not code — future products can have their own cap) -
create table if not exists public.founder_config (
  product    text primary key,
  max_slots  integer not null check (max_slots >= 0)
);
insert into public.founder_config (product, max_slots)
values ('homehuddle', 100)
on conflict (product) do nothing;

-- One founder grant per (family, product). PK prevents a family double-claiming.
create table if not exists public.founder_grants (
  family_id    uuid    not null references public.families(id) on delete cascade,
  product      text    not null default 'homehuddle',
  granted_at   timestamptz not null default now(),
  source       text,               -- stripe | apple | google
  provider_ref text,               -- stripe sub id / apple original_tx / rc app_user_id
  primary key (family_id, product)
);

alter table public.founder_grants enable row level security;
alter table public.founder_config enable row level security;

-- A family may READ whether it holds a founder grant (own family only).
drop policy if exists founder_grants_select_own on public.founder_grants;
create policy founder_grants_select_own on public.founder_grants
  for select to authenticated
  using (family_id in (select current_family_ids(false)));

-- Writes are service_role only (webhooks). No anon/authenticated INSERT.
drop policy if exists founder_grants_service_all on public.founder_grants;
create policy founder_grants_service_all on public.founder_grants
  for all to service_role using (true) with check (true);

-- Config is world-readable (so the join page can show "N of 100 left") but
-- only service_role can change the cap.
drop policy if exists founder_config_read on public.founder_config;
create policy founder_config_read on public.founder_config
  for select to anon, authenticated using (true);
drop policy if exists founder_config_service_all on public.founder_config;
create policy founder_config_service_all on public.founder_config
  for all to service_role using (true) with check (true);

-- ── Atomic claim. Returns true if the family holds (or just won) a slot. ─────
-- Race safety: a transaction-scoped advisory lock keyed by product serializes
-- concurrent claims, so the count-then-insert can never exceed max_slots.
create or replace function public.claim_founder_slot(
  p_family_id uuid,
  p_product   text default 'homehuddle',
  p_source    text default null,
  p_ref       text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max   integer;
  v_count integer;
begin
  -- Serialize all claims for this product.
  perform pg_advisory_xact_lock(hashtext('founder:' || p_product));

  -- Idempotent: already a founder → success.
  if exists (select 1 from public.founder_grants
             where family_id = p_family_id and product = p_product) then
    return true;
  end if;

  select max_slots into v_max from public.founder_config where product = p_product;
  if v_max is null then
    return false;  -- product has no founder program
  end if;

  select count(*) into v_count from public.founder_grants where product = p_product;
  if v_count >= v_max then
    return false;  -- sold out → caller must use Standard pricing
  end if;

  insert into public.founder_grants (family_id, product, source, provider_ref)
  values (p_family_id, p_product, p_source, p_ref);

  -- Mirror onto the canonical entitlement row for fast reads.
  update public.subscriptions
     set founder = true, updated_at = now()
   where family_id = p_family_id and product = p_product;

  return true;
end;
$$;

-- Only backend (service_role) may grant. Never expose to clients.
revoke all on function public.claim_founder_slot(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.claim_founder_slot(uuid, text, text, text) to service_role;

-- Read-only remaining-slots helper for marketing copy (safe for anon).
create or replace function public.founder_slots_remaining(p_product text default 'homehuddle')
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select greatest(0, (select max_slots from public.founder_config where product = p_product)
                     - (select count(*) from public.founder_grants where product = p_product));
$$;
grant execute on function public.founder_slots_remaining(text) to anon, authenticated, service_role;

commit;

-- ROLLBACK (reference):
--   drop function if exists public.founder_slots_remaining(text);
--   drop function if exists public.claim_founder_slot(uuid, text, text, text);
--   drop table if exists public.founder_grants;
--   drop table if exists public.founder_config;

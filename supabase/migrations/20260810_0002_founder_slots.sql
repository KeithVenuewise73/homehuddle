-- ============================================================================
-- 0002 · Founding Family — first-100 slots with RESERVE → GRANT → RELEASE
-- ----------------------------------------------------------------------------
-- CEO-validation fix (V3/V4). Slot lifecycle, all server-side & race-safe:
--   RESERVED  when a family STARTS a Founding subscription/trial (holds a slot)
--   GRANTED   when that trial converts to the FIRST QUALIFYING PAID period
--   RELEASED  if the trial is cancelled/expires WITHOUT ever converting to paid
--             (or a granted founder fully lapses) → the slot returns to the pool
--
-- QUALIFYING EVENT (when a slot is truly consumed/finalized): the first paid
-- period — RevenueCat period_type = NORMAL (TRIAL_CONVERTED / non-trial initial),
-- or Stripe first paid invoice (trialing → active). A checkout that never becomes
-- a paying subscriber does NOT permanently burn a slot: its reservation is released.
--
-- Cap availability counts ACTIVE HOLDS (reserved + granted). A 'released' family
-- is not auto-re-granted Founder (matches "no automatic $4.99 re-entry after
-- losing continuous status") but the freed slot is available to others.
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

create table if not exists public.founder_config (
  product   text primary key,
  max_slots integer not null check (max_slots >= 0)
);
insert into public.founder_config (product, max_slots) values ('homehuddle', 100)
on conflict (product) do nothing;

create table if not exists public.founder_grants (
  family_id    uuid not null references public.families(id) on delete cascade,
  product      text not null default 'homehuddle',
  state        text not null default 'reserved' check (state in ('reserved','granted','released')),
  source       text,
  provider_ref text,
  reserved_at  timestamptz not null default now(),
  granted_at   timestamptz,
  released_at  timestamptz,
  primary key (family_id, product)
);
create index if not exists founder_grants_active_idx
  on public.founder_grants (product) where state in ('reserved','granted');

alter table public.founder_grants enable row level security;
alter table public.founder_config enable row level security;

drop policy if exists founder_grants_select_own on public.founder_grants;
create policy founder_grants_select_own on public.founder_grants
  for select to authenticated using (family_id in (select current_family_ids(false)));
drop policy if exists founder_grants_admin_select on public.founder_grants;
create policy founder_grants_admin_select on public.founder_grants
  for select to authenticated using (public.is_admin());
drop policy if exists founder_grants_service_all on public.founder_grants;
create policy founder_grants_service_all on public.founder_grants
  for all to service_role using (true) with check (true);

drop policy if exists founder_config_read on public.founder_config;
create policy founder_config_read on public.founder_config
  for select to anon, authenticated using (true);
drop policy if exists founder_config_service_all on public.founder_config;
create policy founder_config_service_all on public.founder_config
  for all to service_role using (true) with check (true);

-- ── RESERVE: hold a slot when a Founding trial/subscription starts ───────────
create or replace function public.reserve_founder_slot(
  p_family_id uuid, p_product text default 'homehuddle',
  p_source text default null, p_ref text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_max int; v_active int; v_state text;
begin
  perform pg_advisory_xact_lock(hashtext('founder:' || p_product));

  select state into v_state from public.founder_grants
   where family_id = p_family_id and product = p_product;
  if v_state in ('reserved','granted') then return true;   -- idempotent
  elsif v_state = 'released' then return false;            -- no auto re-entry
  end if;

  select max_slots into v_max from public.founder_config where product = p_product;
  if v_max is null then return false; end if;

  select count(*) into v_active from public.founder_grants
   where product = p_product and state in ('reserved','granted');
  if v_active >= v_max then return false; end if;          -- sold out

  insert into public.founder_grants (family_id, product, state, source, provider_ref)
  values (p_family_id, p_product, 'reserved', p_source, p_ref);
  return true;
end; $$;

-- ── GRANT: finalize the slot on the first qualifying PAID period ─────────────
create or replace function public.grant_founder_slot(
  p_family_id uuid, p_product text default 'homehuddle',
  p_source text default null, p_ref text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_reserved boolean;
begin
  perform pg_advisory_xact_lock(hashtext('founder:' || p_product));

  -- If there is no active hold yet (e.g. race or missing reserve), try to make one.
  if not exists (select 1 from public.founder_grants
                 where family_id = p_family_id and product = p_product
                   and state in ('reserved','granted')) then
    if not public.reserve_founder_slot(p_family_id, p_product, p_source, p_ref) then
      return false;   -- genuinely sold out → caller handles (do not grant Founder)
    end if;
  end if;

  update public.founder_grants
     set state = 'granted', granted_at = coalesce(granted_at, now()),
         source = coalesce(source, p_source), provider_ref = coalesce(provider_ref, p_ref)
   where family_id = p_family_id and product = p_product and state <> 'released';

  update public.subscriptions set founder = true, updated_at = now()
   where family_id = p_family_id and product = p_product;
  return true;
end; $$;

-- ── RELEASE: free a slot when a non-converted trial ends (or founder lapses) ─
create or replace function public.release_founder_slot(
  p_family_id uuid, p_product text default 'homehuddle'
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext('founder:' || p_product));
  update public.founder_grants
     set state = 'released', released_at = now()
   where family_id = p_family_id and product = p_product and state in ('reserved','granted');
  update public.subscriptions set founder = false, updated_at = now()
   where family_id = p_family_id and product = p_product;
end; $$;

revoke all on function public.reserve_founder_slot(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.grant_founder_slot(uuid,text,text,text)   from public, anon, authenticated;
revoke all on function public.release_founder_slot(uuid,text)           from public, anon, authenticated;
grant execute on function public.reserve_founder_slot(uuid,text,text,text) to service_role;
grant execute on function public.grant_founder_slot(uuid,text,text,text)   to service_role;
grant execute on function public.release_founder_slot(uuid,text)           to service_role;

-- Read-only remaining slots (active holds) — safe for marketing copy.
create or replace function public.founder_slots_remaining(p_product text default 'homehuddle')
returns integer language sql stable security definer set search_path = public as $$
  select greatest(0, (select max_slots from public.founder_config where product = p_product)
                     - (select count(*) from public.founder_grants
                        where product = p_product and state in ('reserved','granted')));
$$;
grant execute on function public.founder_slots_remaining(text) to anon, authenticated, service_role;

commit;

-- ROLLBACK (reference):
--   drop function if exists public.founder_slots_remaining(text);
--   drop function if exists public.release_founder_slot(uuid,text);
--   drop function if exists public.grant_founder_slot(uuid,text,text,text);
--   drop function if exists public.reserve_founder_slot(uuid,text,text,text);
--   drop table if exists public.founder_grants;
--   drop table if exists public.founder_config;

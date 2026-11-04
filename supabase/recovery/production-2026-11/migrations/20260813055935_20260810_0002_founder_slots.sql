
-- 0002 · Founding Family — first-100 slots with RESERVE → GRANT → RELEASE

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
  if v_state in ('reserved','granted') then return true;
  elsif v_state = 'released' then return false;
  end if;

  select max_slots into v_max from public.founder_config where product = p_product;
  if v_max is null then return false; end if;

  select count(*) into v_active from public.founder_grants
   where product = p_product and state in ('reserved','granted');
  if v_active >= v_max then return false; end if;

  insert into public.founder_grants (family_id, product, state, source, provider_ref)
  values (p_family_id, p_product, 'reserved', p_source, p_ref);
  return true;
end; $$;

create or replace function public.grant_founder_slot(
  p_family_id uuid, p_product text default 'homehuddle',
  p_source text default null, p_ref text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_reserved boolean;
begin
  perform pg_advisory_xact_lock(hashtext('founder:' || p_product));

  if not exists (select 1 from public.founder_grants
                 where family_id = p_family_id and product = p_product
                   and state in ('reserved','granted')) then
    if not public.reserve_founder_slot(p_family_id, p_product, p_source, p_ref) then
      return false;
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

create or replace function public.release_founder_slot(
  p_family_id uuid, p_product text default 'homehuddle'
) returns text
language plpgsql security definer set search_path = public as $$
declare v_state text;
begin
  perform pg_advisory_xact_lock(hashtext('founder:' || p_product));
  select state into v_state from public.founder_grants
   where family_id = p_family_id and product = p_product;

  if v_state = 'granted' then
    return 'kept_granted';
  elsif v_state = 'reserved' then
    update public.founder_grants
       set state = 'released', released_at = now()
     where family_id = p_family_id and product = p_product and state = 'reserved';
    update public.subscriptions set founder = false, updated_at = now()
     where family_id = p_family_id and product = p_product;
    return 'released_reservation';
  end if;
  return 'noop';
end; $$;

revoke all on function public.reserve_founder_slot(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.grant_founder_slot(uuid,text,text,text)   from public, anon, authenticated;
revoke all on function public.release_founder_slot(uuid,text)           from public, anon, authenticated;
grant execute on function public.reserve_founder_slot(uuid,text,text,text) to service_role;
grant execute on function public.grant_founder_slot(uuid,text,text,text)   to service_role;
grant execute on function public.release_founder_slot(uuid,text)           to service_role;

create or replace function public.founder_slots_remaining(p_product text default 'homehuddle')
returns integer language sql stable security definer set search_path = public as $$
  select greatest(0, (select max_slots from public.founder_config where product = p_product)
                     - (select count(*) from public.founder_grants
                        where product = p_product and state in ('reserved','granted')));
$$;
grant execute on function public.founder_slots_remaining(text) to anon, authenticated, service_role;

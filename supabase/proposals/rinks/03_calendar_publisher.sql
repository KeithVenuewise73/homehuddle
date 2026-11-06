-- Candidate only. Repairs the existing, unattached calendar hub writer instead of adding a second one.
-- VERIFIED 2026-11-06 (read-only): public.publish_to_calendar has no callers (0 functions, 0 triggers,
-- 0 cron jobs) and EXECUTE only for postgres/service_role, so this changes no existing behaviour.
-- Two defects fixed:
--   1. default p_status 'confirmed' violated calendar_events_status_check (active|cancelled|completed),
--      so any call omitting p_status failed;
--   2. update-then-insert raced: two first-time publishes of one source could collide on the unique key.
-- Signature, security definer, search_path, the homehuddle guard and grants are unchanged.
begin;
create or replace function public.publish_to_calendar(
  p_source_module text, p_source_table text, p_source_id text, p_title text, p_start_time timestamptz,
  p_end_time timestamptz default null, p_event_type text default null, p_description text default null,
  p_location_name text default null, p_location_address text default null, p_organization_id uuid default null,
  p_coach_id uuid default null, p_facility_id uuid default null, p_is_public boolean default false,
  p_status text default 'active')
returns uuid language plpgsql security definer set search_path = public, pg_temp as $fn$
declare v_id uuid;
begin
  if p_source_module is null or p_source_module = 'homehuddle' then
    raise exception 'publish_to_calendar: invalid source_module %', p_source_module;
  end if;
  if p_source_table is null or p_source_id is null then
    raise exception 'publish_to_calendar: source_table and source_id are required';
  end if;
  if p_start_time is null then
    raise exception 'publish_to_calendar: start_time is required';
  end if;
  insert into public.calendar_events (source_module, source_table, source_id, title, description, event_type,
    start_time, end_time, location_name, location_address, organization_id, coach_id, facility_id, is_public, status)
  values (p_source_module, p_source_table, p_source_id, p_title, p_description, p_event_type,
    p_start_time, p_end_time, p_location_name, p_location_address, p_organization_id, p_coach_id, p_facility_id, p_is_public, p_status)
  on conflict (source_module, source_table, source_id) do update set
    title = excluded.title, description = excluded.description, event_type = excluded.event_type,
    start_time = excluded.start_time, end_time = excluded.end_time, location_name = excluded.location_name,
    location_address = excluded.location_address, organization_id = excluded.organization_id,
    coach_id = excluded.coach_id, facility_id = excluded.facility_id, is_public = excluded.is_public,
    status = excluded.status, updated_at = now()
  returning id into v_id;
  return v_id;
end $fn$;
revoke all on function public.publish_to_calendar(text,text,text,text,timestamptz,timestamptz,text,text,text,text,uuid,uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.publish_to_calendar(text,text,text,text,timestamptz,timestamptz,text,text,text,text,uuid,uuid,uuid,boolean,text) to service_role;
commit;

create or replace function public.publish_to_calendar(
  p_source_module   text,
  p_source_table    text,
  p_source_id       text,
  p_title           text,
  p_start_time      timestamptz,
  p_end_time        timestamptz default null,
  p_event_type      text default null,
  p_description     text default null,
  p_location_name   text default null,
  p_location_address text default null,
  p_organization_id uuid default null,
  p_coach_id        uuid default null,
  p_facility_id     uuid default null,
  p_is_public       boolean default false,
  p_status          text default 'confirmed'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_id uuid;
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

  update public.calendar_events
     set title            = p_title,
         description      = p_description,
         event_type       = p_event_type,
         start_time       = p_start_time,
         end_time         = p_end_time,
         location_name    = p_location_name,
         location_address = p_location_address,
         organization_id  = p_organization_id,
         coach_id         = p_coach_id,
         facility_id      = p_facility_id,
         is_public        = p_is_public,
         status           = p_status,
         updated_at       = now()
   where source_module = p_source_module
     and source_table  = p_source_table
     and source_id     = p_source_id
   returning id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.calendar_events (
    source_module, source_table, source_id, title, description, event_type,
    start_time, end_time, location_name, location_address,
    organization_id, coach_id, facility_id, is_public, status
  ) values (
    p_source_module, p_source_table, p_source_id, p_title, p_description, p_event_type,
    p_start_time, p_end_time, p_location_name, p_location_address,
    p_organization_id, p_coach_id, p_facility_id, p_is_public, p_status
  )
  returning id into v_id;

  return v_id;
end $fn$;

revoke all on function public.publish_to_calendar(
  text,text,text,text,timestamptz,timestamptz,text,text,text,text,uuid,uuid,uuid,boolean,text
) from public, anon, authenticated;

comment on function public.publish_to_calendar is
  'Single gated write path into calendar_events for non-HomeHuddle modules. Created Phase 1, unattached. Callers wired in Phase 3.';
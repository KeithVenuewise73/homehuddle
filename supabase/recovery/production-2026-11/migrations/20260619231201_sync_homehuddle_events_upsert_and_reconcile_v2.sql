drop function if exists public.sync_homehuddle_events_to_calendar();

create function public.sync_homehuddle_events_to_calendar()
returns table(inserted_count integer, updated_count integer, cancelled_count integer)
language plpgsql
as $function$
declare
  v_inserted integer := 0;
  v_updated  integer := 0;
  v_cancelled integer := 0;
begin
  with affected as (
    insert into public.calendar_events (
      source_module, source_table, source_id,
      title, description, event_type, start_time, end_time,
      location_name, is_public, status, is_conflict, is_duplicate,
      created_at, updated_at
    )
    select
      'homehuddle', 'events', e.uid || '::' || e.kid,
      e.name, e.description, e.sport, e."start", e."end",
      e.location, false,
      case when coalesce(e.is_duplicate, false) then 'cancelled' else 'active' end,
      coalesce(e.conflict, false),
      coalesce(e.is_duplicate, false),
      coalesce(e.synced_at, now()), coalesce(e.updated_at, now())
    from public.events e
    on conflict (source_module, source_table, source_id) do update
      set title         = excluded.title,
          description   = excluded.description,
          event_type    = excluded.event_type,
          start_time    = excluded.start_time,
          end_time      = excluded.end_time,
          location_name = excluded.location_name,
          status        = excluded.status,
          is_conflict   = excluded.is_conflict,
          is_duplicate  = excluded.is_duplicate,
          updated_at    = now()
      where calendar_events.title         is distinct from excluded.title
         or calendar_events.description   is distinct from excluded.description
         or calendar_events.event_type    is distinct from excluded.event_type
         or calendar_events.start_time    is distinct from excluded.start_time
         or calendar_events.end_time      is distinct from excluded.end_time
         or calendar_events.location_name is distinct from excluded.location_name
         or calendar_events.status        is distinct from excluded.status
         or calendar_events.is_conflict   is distinct from excluded.is_conflict
         or calendar_events.is_duplicate  is distinct from excluded.is_duplicate
    returning (xmax = 0) as was_insert
  )
  select count(*) filter (where was_insert),
         count(*) filter (where not was_insert)
    into v_inserted, v_updated
  from affected;

  update public.calendar_events ce
     set status = 'cancelled', updated_at = now()
   where ce.source_module = 'homehuddle'
     and ce.source_table  = 'events'
     and ce.status <> 'cancelled'
     and not exists (
       select 1 from public.events e
       where e.uid || '::' || e.kid = ce.source_id
     );
  get diagnostics v_cancelled = row_count;

  return query select v_inserted, v_updated, v_cancelled;
end;
$function$;
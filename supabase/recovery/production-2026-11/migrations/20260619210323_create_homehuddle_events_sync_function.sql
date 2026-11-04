-- Manually-invoked batch sync: copies rows from the live, untouched
-- `events` table (HomeHuddle's GameChanger/TeamSnap/iCal pipeline)
-- into the shared calendar_events layer. Safe to call repeatedly —
-- duplicates are prevented by the unique constraint on
-- (source_module, source_table, source_id), enforced via
-- ON CONFLICT DO NOTHING.
--
-- This does NOT run automatically. Call it manually:
--   select * from sync_homehuddle_events_to_calendar();
-- A scheduled job (pg_cron or external) can be added later, once
-- this has been verified manually.

create or replace function sync_homehuddle_events_to_calendar()
returns table(inserted_count integer, skipped_count integer) as $$
declare
  v_inserted integer := 0;
  v_skipped integer := 0;
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from public.calendar_events where source_module = 'homehuddle';

  insert into public.calendar_events (
    source_module, source_table, source_id,
    title, description, event_type, start_time, end_time,
    location_name, is_public, status, created_at, updated_at
  )
  select
    'homehuddle',
    'events',
    e.uid || '::' || e.kid,
    e.name,
    e.description,
    e.sport,
    e.start,
    e."end",
    e.location,
    false,
    case when e.is_duplicate then 'cancelled' else 'active' end,
    e.synced_at,
    e.updated_at
  from public.events e
  on conflict (source_module, source_table, source_id) do nothing;

  select count(*) into v_after from public.calendar_events where source_module = 'homehuddle';
  v_inserted := v_after - v_before;
  select count(*) into v_skipped from public.events;
  v_skipped := v_skipped - v_inserted;

  return query select v_inserted, v_skipped;
end;
$$ language plpgsql;
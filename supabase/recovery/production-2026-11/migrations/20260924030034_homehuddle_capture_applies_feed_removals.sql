create or replace function public.capture_sync_reports()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  j jsonb;
  v_outcome text;
  n integer := 0;
begin
  for r in
    select s.id, h.status_code, h.timed_out, h.error_msg, h.content
      from public.sync_reports s
      join net._http_response h on h.id = s.request_id
     where s.outcome = 'running'
     order by s.started_at
  loop
    begin
      j := r.content::jsonb;
    exception when others then
      j := null;
    end;
    v_outcome := case
                   when r.timed_out then 'timed_out'
                   when r.error_msg is not null then 'failed'
                   when r.status_code between 200 and 299 then 'ok'
                   else 'http_error'
                 end;
    update public.sync_reports set
      captured_at = now(),
      status_code = r.status_code,
      error       = r.error_msg,
      report      = j,
      raw_body    = case when j is null then left(r.content, 4000) end,
      outcome     = v_outcome
     where id = r.id;

    -- Events the team deleted at the source come off the family calendar.
    -- Only a newer run can see further removals, so skip superseded reports.
    if v_outcome = 'ok' and not exists (
         select 1 from public.sync_reports s2
          where s2.outcome = 'ok' and s2.started_at > (select started_at from public.sync_reports where id = r.id)
       ) then
      update public.sync_reports
         set removals = public.remove_events_missing_from_feed(r.id, false)
       where id = r.id;
    end if;
    n := n + 1;
  end loop;

  update public.sync_reports
     set outcome = 'lost', captured_at = now()
   where outcome = 'running' and started_at < now() - interval '6 hours';

  return n;
end;
$$;
revoke all on function public.capture_sync_reports() from public, anon, authenticated;

-- Apply to the latest report already captured (01:00 UTC run).
update public.sync_reports s
   set removals = public.remove_events_missing_from_feed(s.id, false)
 where s.id = (select id from public.sync_reports where outcome = 'ok' order by started_at desc limit 1)
   and s.removals is null;
-- Safety net: any lead still 'new' after 24h gets re-surfaced once per day.
-- Catches the exact failure mode that let 20 leads go cold.
create or replace function public.escalate_stale_leads()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stale integer;
  v_oldest integer;
begin
  select count(*), coalesce(max(extract(day from now() - created_at))::int, 0)
    into v_stale, v_oldest
  from public.leads
  where status = 'new' and created_at < now() - interval '24 hours';

  if v_stale = 0 then
    return 0;
  end if;

  perform public.enqueue_internal_alert(
    'lead',
    'stale-digest:' || current_date::text,
    'UNWORKED LEADS: ' || v_stale::text
      || E'\nOldest is ' || v_oldest::text || ' days cold.'
      || E'\nOpen the leads board and clear them.'
  );
  return v_stale;
end;
$$;

select cron.schedule(
  'escalate-stale-leads-daily',
  '0 13 * * *',  -- 13:00 UTC = 9am ET
  $cron$select public.escalate_stale_leads();$cron$
);
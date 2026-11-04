create or replace function public.refresh_platform_status()
returns void language plpgsql security definer as $$
begin
  -- one row per feed (active AND inactive); inactive feeds are surfaced as status='inactive'
  insert into public.platform_status
    (feed_id, platform, kid, event_count, last_sync, last_success, status, last_error, updated_at)
  select
    f.id,
    f.platform,
    f.kid_name,
    (select count(*) from public.events e where e.feed_id = f.id and not coalesce(e.is_duplicate,false)),
    (select max(e.updated_at) from public.events e where e.feed_id = f.id),
    (select max(e.updated_at) from public.events e where e.feed_id = f.id),
    case
      when not f.is_active then 'inactive'
      when (select count(*) from public.events e where e.feed_id = f.id) = 0 then 'no_events'
      when (select max(e.updated_at) from public.events e where e.feed_id = f.id) > now() - interval '90 minutes' then 'connected'
      else 'stale'
    end,
    null,  -- last_error: not derivable DB-side; future Edge Function change only (Phase B)
    now()
  from public.feeds f
  on conflict (feed_id) do update set
    platform     = excluded.platform,
    kid          = excluded.kid,
    event_count  = excluded.event_count,
    last_sync    = excluded.last_sync,
    last_success = coalesce(excluded.last_success, public.platform_status.last_success),
    status       = excluded.status,
    updated_at   = now();
end;
$$;
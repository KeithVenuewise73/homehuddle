-- Remove events a team deleted at the source (approved by Keith 2026-09-24).
-- sync-schedules only ever inserts/updates, so cancelled games stayed on the
-- family calendar forever. Every in-window event present in a feed gets its
-- updated_at bumped by the sync, so a FUTURE event of a cleanly-synced feed
-- whose updated_at is older than that run was not in the feed.

create table public.events_removed (like public.events);
alter table public.events_removed
  add column removed_at        timestamptz not null default now(),
  add column removed_by_report bigint,
  add column reason            text;
comment on table public.events_removed is
  'Events removed because their source feed no longer lists them. Archive, not trash: a row can be copied back into public.events.';
alter table public.events_removed enable row level security;
revoke all on public.events_removed from anon, authenticated;

alter table public.sync_reports add column removals jsonb;

create or replace function public.remove_events_missing_from_feed(
  p_report_id bigint,
  p_dry_run   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rep     public.sync_reports%rowtype;
  fr      jsonb;
  v_feed  public.feeds%rowtype;
  n_match integer;
  n_future integer;
  cand    jsonb;
  n_cand  integer;
  out     jsonb := '[]'::jsonb;
begin
  select * into rep from public.sync_reports where id = p_report_id;
  if rep.id is null or rep.outcome <> 'ok' or rep.report is null then
    return jsonb_build_object('skipped', 'report not ok');
  end if;

  for fr in select * from jsonb_array_elements(coalesce(rep.report->'feeds', '[]'::jsonb))
  loop
    -- Only act on a feed that was read completely and saved without error.
    if coalesce((fr->>'fetched')::int, 0) = 0
       or coalesce((fr->>'skipped')::int, 0) > 0
       or jsonb_array_length(coalesce(fr->'errors', '[]'::jsonb)) > 0 then
      out := out || jsonb_build_object('team', fr->>'team', 'action', 'none',
               'why', 'feed not read cleanly');
      continue;
    end if;

    select count(*) into n_match from public.feeds f
     where f.is_active and f.platform = fr->>'platform'
       and f.kid_name = fr->>'kid' and f.family_name = fr->>'family'
       and coalesce(f.team_name, '') = coalesce(fr->>'team', '');
    if n_match <> 1 then
      out := out || jsonb_build_object('team', fr->>'team', 'action', 'none',
               'why', 'could not identify feed');
      continue;
    end if;
    select * into v_feed from public.feeds f
     where f.is_active and f.platform = fr->>'platform'
       and f.kid_name = fr->>'kid' and f.family_name = fr->>'family'
       and coalesce(f.team_name, '') = coalesce(fr->>'team', '');

    -- Future and inside the sync's own window (it only refreshes up to +365 d).
    select count(*) into n_future from public.events e
     where e.feed_id = v_feed.id and e.start > now() and e.start < now() + interval '360 days';

    select coalesce(jsonb_agg(jsonb_build_object('uid', e.uid, 'kid', e.kid, 'name', e.name, 'start', e.start)), '[]'::jsonb),
           count(*)
      into cand, n_cand
      from public.events e
     where e.feed_id = v_feed.id
       and e.start > now() and e.start < now() + interval '360 days'
       and e.updated_at < rep.started_at;

    if n_cand = 0 then
      continue;
    end if;

    -- Brake: a feed that suddenly "loses" many games is more likely broken.
    if n_cand > greatest(3, n_future / 4) then
      out := out || jsonb_build_object('team', fr->>'team', 'action', 'held',
               'why', format('%s of %s upcoming events missing; too many to trust', n_cand, n_future),
               'events', cand);
      continue;
    end if;

    if not p_dry_run then
      insert into public.events_removed
        select e.*, now(), rep.id, 'no longer in source feed'
          from public.events e
         where e.feed_id = v_feed.id
           and e.start > now() and e.start < now() + interval '360 days'
           and e.updated_at < rep.started_at;
      delete from public.events e
       where e.feed_id = v_feed.id
         and e.start > now() and e.start < now() + interval '360 days'
         and e.updated_at < rep.started_at;
    end if;

    out := out || jsonb_build_object('team', fr->>'team',
             'action', case when p_dry_run then 'would_remove' else 'removed' end,
             'events', cand);
  end loop;

  return jsonb_build_object('feeds', out);
end;
$$;
revoke all on function public.remove_events_missing_from_feed(bigint, boolean) from public, anon, authenticated;
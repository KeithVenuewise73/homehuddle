-- One schedule text per family per sync (approved by Keith 2026-09-28).
-- Before: trg_events_sms queued one text per changed event per family member,
-- so 34 new TeamSnap events = 136 texts in 3 seconds. Now changes are held
-- in schedule_change_queue and flush_schedule_digests() sends one text per
-- family once that family's changes have been quiet for a few minutes.

create table public.schedule_change_queue (
  id          bigint generated always as identity primary key,
  family_id   uuid not null,
  family_name text,
  event_ref   text not null,          -- same logical identity the trigger always used
  change_hash text not null,
  kind        text not null check (kind in ('new', 'changed')),
  event_name  text,
  event_start timestamptz,
  created_at  timestamptz not null default now(),
  flushed_at  timestamptz,
  digest_ref  text,
  unique (family_id, event_ref, change_hash)
);
create index schedule_change_queue_pending_idx
  on public.schedule_change_queue (family_id) where flushed_at is null;
comment on table public.schedule_change_queue is
  'Schedule changes waiting to be texted. flush_schedule_digests() turns each family''s batch into ONE text.';
alter table public.schedule_change_queue enable row level security;
revoke all on public.schedule_change_queue from anon, authenticated;

-- Same filters and identity as before; only the destination changes.
create or replace function public.trg_events_sms()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_new_hash text;
  v_old_hash text;
  v_family   uuid;
  v_famname  text;
  v_ref      text;
begin
  if new."start" is null or new."start" <= now() or coalesce(new.is_duplicate, false) then
    return new;
  end if;

  v_new_hash := md5(
    coalesce(new.name,'') || '|' || coalesce(new."start"::text,'') || '|' ||
    coalesce(new."end"::text,'') || '|' || coalesce(new.location,'')
  );

  if tg_op = 'UPDATE' then
    v_old_hash := md5(
      coalesce(old.name,'') || '|' || coalesce(old."start"::text,'') || '|' ||
      coalesce(old."end"::text,'') || '|' || coalesce(old.location,'')
    );
    if v_old_hash = v_new_hash then
      return new;
    end if;
  end if;

  select fam.id, fam.family_name into v_family, v_famname
  from public.feeds f
  join public.families fam on fam.email = f.email
  where f.id = new.feed_id
  limit 1;

  if v_family is null then
    return new;
  end if;

  v_ref := 'ev:' || v_family::text || ':' ||
           md5(lower(coalesce(new.name,'')) || '|' ||
               to_char(new."start" at time zone 'America/New_York','YYYY-MM-DD'));

  -- Never text the same change twice (it may have gone out before this change).
  if exists (select 1 from public.sms_outbox o
              where o.event_ref = v_ref and o.change_hash = v_new_hash) then
    return new;
  end if;

  -- A texting problem must never stop a schedule from saving.
  begin
    insert into public.schedule_change_queue
      (family_id, family_name, event_ref, change_hash, kind, event_name, event_start)
    values
      (v_family, v_famname, v_ref, v_new_hash,
       case when tg_op = 'INSERT' then 'new' else 'changed' end,
       new.name, new."start")
    on conflict do nothing;
  exception when others then
    null;
  end;
  return new;
end;
$function$;

create or replace function public.flush_schedule_digests(p_quiet interval default interval '3 minutes')
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  fam       record;
  it        record;
  v_n       int;
  v_new     int;
  v_chg     int;
  v_first   text;
  v_words   text[];
  v_prefix  text := '';
  v_try     text;
  v_msg     text;
  v_item    text;
  v_shown   int;
  v_ref     text;
  v_out     jsonb := '[]'::jsonb;
begin
  for fam in
    select q.family_id, max(q.family_name) as family_name, min(q.id) as first_id
      from public.schedule_change_queue q
     where q.flushed_at is null
     group by q.family_id
    having max(q.created_at) < now() - p_quiet
  loop
    -- Latest change per event; drop events that have already started.
    create temporary table if not exists _batch (event_ref text, kind text, event_name text, event_start timestamptz) on commit drop;
    truncate _batch;
    insert into _batch
      select distinct on (q.event_ref) q.event_ref,
             -- an event that is new in this batch stays "new" even if it changed again
             case when bool_or(q.kind = 'new') over (partition by q.event_ref) then 'new' else q.kind end,
             q.event_name, q.event_start
        from public.schedule_change_queue q
       where q.family_id = fam.family_id and q.flushed_at is null
       order by q.event_ref, q.id desc;
    delete from _batch where event_start <= now();

    select count(*), count(*) filter (where kind = 'new'), count(*) filter (where kind = 'changed')
      into v_n, v_new, v_chg from _batch;

    if v_n = 1 then
      -- Exactly the text families have always received for a single change.
      select * into it from _batch;
      v_msg := coalesce(fam.family_name, 'HomeHuddle') || ' — ' ||
               case when it.kind = 'new' then 'New: ' else 'Schedule change: ' end ||
               coalesce(it.event_name, 'event') || ' ' ||
               to_char(it.event_start at time zone 'America/New_York', 'Dy Mon FMDD at FMHH12:MI AM');
    elsif v_n > 1 then
      -- Shared leading words (e.g. the team name) are said once, not per line.
      select event_name into v_first from _batch order by event_start limit 1;
      v_words := regexp_split_to_array(coalesce(v_first, ''), '\s+');
      v_prefix := '';
      for i in 1 .. coalesce(array_length(v_words, 1), 0) - 1 loop
        v_try := array_to_string(v_words[1:i], ' ');
        exit when exists (select 1 from _batch b where coalesce(b.event_name, '') not like v_try || ' %');
        v_prefix := v_try;
      end loop;

      -- Plain characters only: keeps each text in the cheapest SMS encoding.
      v_msg := coalesce(fam.family_name, 'HomeHuddle') || ': ' ||
               v_n || ' schedule updates' ||
               case when v_prefix <> '' then ' for ' || v_prefix else '' end ||
               ' (' || v_new || ' new, ' || v_chg || ' changed). Next:';
      v_shown := 0;
      for it in select * from _batch order by event_start loop
        v_item := ' ' || to_char(it.event_start at time zone 'America/New_York', 'Dy Mon FMDD FMHH12:MIam') || ' ' ||
                  btrim(regexp_replace(substr(coalesce(it.event_name, 'event'), length(v_prefix) + 1), '^\s*-\s*', '')) || ';';
        exit when v_shown >= 3 or length(v_msg || v_item) > 250;
        v_msg := v_msg || v_item;
        v_shown := v_shown + 1;
      end loop;
      v_msg := rtrim(v_msg, ';') || '. Full schedule: venuewise.net';
    end if;

    v_ref := 'digest:' || fam.family_id::text || ':' || fam.first_id::text;
    if v_n > 0 then
      perform public.enqueue_sms_for_family(fam.family_id, null, v_ref, md5(v_msg), v_msg);
    end if;

    update public.schedule_change_queue
       set flushed_at = now(), digest_ref = case when v_n > 0 then v_ref end
     where family_id = fam.family_id and flushed_at is null;

    v_out := v_out || jsonb_build_object('family', fam.family_name, 'changes', v_n, 'message', v_msg);
  end loop;
  return v_out;
end;
$function$;
revoke all on function public.flush_schedule_digests(interval) from public, anon, authenticated;

select cron.schedule('flush-schedule-digests', '*/2 * * * *', 'select public.flush_schedule_digests();');
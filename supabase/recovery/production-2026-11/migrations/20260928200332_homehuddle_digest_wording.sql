-- Date/time wording for schedule texts. All-day events are stored at local
-- midnight and used to read "12:00 AM"; they now show the date only.
create or replace function public.schedule_when(p_start timestamptz, p_long boolean default true)
returns text
language sql
immutable
set search_path to ''
as $$
  select case
    when (p_start at time zone 'America/New_York')::time = time '00:00'
      then to_char(p_start at time zone 'America/New_York', 'Dy Mon FMDD')
    when p_long
      then to_char(p_start at time zone 'America/New_York', 'Dy Mon FMDD "at" FMHH12:MI AM')
    else to_char(p_start at time zone 'America/New_York', 'Dy Mon FMDD FMHH12:MIam')
  end
$$;

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
    create temporary table if not exists _batch (event_ref text, kind text, event_name text, event_start timestamptz) on commit drop;
    truncate _batch;
    insert into _batch
      select distinct on (q.event_ref) q.event_ref,
             case when bool_or(q.kind = 'new') over (partition by q.event_ref) then 'new' else q.kind end,
             q.event_name, q.event_start
        from public.schedule_change_queue q
       where q.family_id = fam.family_id and q.flushed_at is null
       order by q.event_ref, q.id desc;
    delete from _batch where event_start <= now();

    select count(*), count(*) filter (where kind = 'new'), count(*) filter (where kind = 'changed')
      into v_n, v_new, v_chg from _batch;

    if v_n = 1 then
      select * into it from _batch;
      v_msg := coalesce(fam.family_name, 'HomeHuddle') || ' — ' ||
               case when it.kind = 'new' then 'New: ' else 'Schedule change: ' end ||
               coalesce(it.event_name, 'event') || ' ' || public.schedule_when(it.event_start, true);
    elsif v_n > 1 then
      select event_name into v_first from _batch order by event_start limit 1;
      v_words := regexp_split_to_array(coalesce(v_first, ''), '\s+');
      v_prefix := '';
      for i in 1 .. coalesce(array_length(v_words, 1), 0) - 1 loop
        v_try := array_to_string(v_words[1:i], ' ');
        exit when exists (select 1 from _batch b where coalesce(b.event_name, '') not like v_try || ' %');
        v_prefix := v_try;
      end loop;

      v_msg := coalesce(fam.family_name, 'HomeHuddle') || ': ' ||
               v_n || ' schedule updates' ||
               case when v_prefix <> '' then ' for ' || v_prefix else '' end ||
               ' (' || concat_ws(', ',
                         case when v_new > 0 then v_new || ' new' end,
                         case when v_chg > 0 then v_chg || ' changed' end) ||
               '). Next:';
      v_shown := 0;
      for it in select * from _batch order by event_start loop
        v_item := ' ' || public.schedule_when(it.event_start, false) || ' ' ||
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
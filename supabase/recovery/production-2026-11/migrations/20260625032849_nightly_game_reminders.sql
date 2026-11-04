
create or replace function public.enqueue_nightly_reminders(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_hour    int  := extract(hour from (now() at time zone 'America/New_York'));
  v_tom     date := (now() at time zone 'America/New_York')::date + 1;
  v_label   text := to_char((now() at time zone 'America/New_York')::date + 1, 'Dy FMMM/FMDD');
  v_ref     text := 'nightly:' || ((now() at time zone 'America/New_York')::date + 1)::text;
  r         record;
  v_msg     text;
  v_hash    text;
  v_fam     int := 0;
  v_rows    int := 0;
  v_n       int;
begin
  -- Fire only during the 5pm Eastern hour (DST-proof), unless forced for testing.
  if not p_force and v_hour <> 17 then
    return jsonb_build_object('ran', false, 'eastern_hour', v_hour, 'reason', 'outside 5pm hour');
  end if;

  for r in
    select fam.id as family_id,
           string_agg(
             '• ' || coalesce(nullif(e.kid,''),'Family') || ': ' || e.name ||
             ' — ' || to_char(e.start at time zone 'America/New_York','FMHH12:MI PM'),
             E'\n' order by e.start
           ) as lines
    from families fam
    join feeds  f on f.email = fam.email
    join events e on e.feed_id = f.id
    where (e.start at time zone 'America/New_York')::date = v_tom
      and coalesce(e.is_duplicate, false) = false
    group by fam.id
  loop
    v_fam := v_fam + 1;
    v_msg := E'\U0001F3E0 HomeHuddle \u2014 tomorrow (' || v_label || E'):\n'
             || r.lines || E'\n\nReply STOP to opt out.';
    v_hash := md5(v_msg);

    insert into public.sms_outbox (person_id, phone, family_id, event_ref, change_hash, message, status)
    select p.id, p.phone, r.family_id, v_ref, v_hash, v_msg, 'pending'
    from public.family_access fa
    join public.people p on p.id = fa.person_id
    where fa.family_id = r.family_id
      and fa.status = 'active'
      and p.phone_verified = true
      and coalesce(p.sms_opt_in, true) = true
      and p.phone is not null
    on conflict (person_id, event_ref, change_hash) do nothing;

    get diagnostics v_n = row_count;
    v_rows := v_rows + v_n;
  end loop;

  return jsonb_build_object('ran', true, 'tomorrow', v_tom, 'families', v_fam, 'enqueued', v_rows);
end;
$$;

revoke all on function public.enqueue_nightly_reminders(boolean) from public, anon, authenticated;

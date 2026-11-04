-- Shows the family owner every number they just added, so a wrong digit is
-- visible to the one person who knows the right one.
create or replace function public.queue_owner_member_summary(p_family_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_owner_ph  text; v_owner_pid uuid; v_lines text; v_msg text; v_n int;
begin
  select p.id, p.phone into v_owner_pid, v_owner_ph
  from public.people p
  join public.family_access fa on fa.person_id = p.id
  where fa.family_id = p_family_id and fa.role='owner' and fa.status='active'
  limit 1;

  if v_owner_ph is null then
    select phone into v_owner_ph from public.families where id = p_family_id;
  end if;
  if v_owner_ph is null then return false; end if;

  select string_agg(fm.name || ' ' || public.format_phone_display(fm.phone), E'\n' order by fm.name),
         count(*)
    into v_lines, v_n
  from public.family_members fm
  where fm.family_id = p_family_id
    and fm.phone is not null and btrim(fm.phone) <> ''
    and fm.phone is distinct from v_owner_ph
    and coalesce(fm.receives_sms,true) = true;

  if coalesce(v_n,0) = 0 then return false; end if;

  v_msg := 'HomeHuddle: we asked these people to confirm reminders:' || E'\n'
           || v_lines || E'\n\nIf a number looks wrong, fix it in your account.';

  insert into public.sms_outbox (person_id, phone, family_id, event_ref, change_hash, message, status)
  values (v_owner_pid, v_owner_ph, p_family_id,
          'member-summary:' || p_family_id::text, md5(v_msg), v_msg, 'pending')
  on conflict do nothing;

  return true;
end;
$$;
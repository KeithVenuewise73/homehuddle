-- Queues the double opt-in request for one family member.
-- Wording matches the existing July 23 message exactly.
-- sms-inbound already handles the YES/STOP reply; this is the missing send half.
create or replace function public.queue_member_confirmation(
  p_member_id uuid,
  p_added_by  text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  m         record;
  v_family  text;
  v_adder   text;
  v_msg     text;
  v_person  uuid;
begin
  select fm.*, f.family_name into m
  from public.family_members fm
  join public.families f on f.id = fm.family_id
  where fm.id = p_member_id;

  if not found then return false; end if;

  -- Nothing to send to, already settled, or SMS not wanted.
  if m.phone is null or btrim(m.phone) = '' then return false; end if;
  if coalesce(m.receives_sms, true) = false      then return false; end if;
  if m.sms_status in ('confirmed','declined','pending') then return false; end if;

  v_family := m.family_name;

  v_adder := coalesce(
    p_added_by,
    (select p.display_name from public.people p
       join public.family_access fa on fa.person_id = p.id
      where fa.family_id = m.family_id and fa.role = 'owner'
      limit 1),
    'Someone'
  );

  v_msg := 'HomeHuddle: ' || v_adder || ' added you to the ' || v_family ||
           ' sports calendar. Reply YES to get game reminders, STOP to opt out.';

  select id into v_person from public.people where phone = m.phone limit 1;

  insert into public.sms_outbox
    (person_id, phone, family_id, event_ref, change_hash, message, status)
  values
    (v_person, m.phone, m.family_id,
     'confirm:' || p_member_id::text, md5(v_msg), v_msg, 'pending')
  on conflict do nothing;

  update public.family_members
     set sms_status = 'pending', sms_confirm_sent_at = now()
   where id = p_member_id;

  return true;
end;
$$;
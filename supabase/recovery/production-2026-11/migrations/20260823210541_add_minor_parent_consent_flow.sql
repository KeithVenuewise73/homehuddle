-- Readable number for parent-facing messages, so a typo is visible.
create or replace function public.format_phone_display(p text)
returns text language sql immutable as $$
  select case when p ~ '^\+1\d{10}$'
    then '(' || substr(p,3,3) || ') ' || substr(p,6,3) || '-' || substr(p,9,4)
    else coalesce(p,'') end;
$$;

-- Under 13: consent is requested from the PARENT, and the child's number is
-- shown so a mistyped digit is caught by the one person who knows it.
create or replace function public.queue_member_confirmation(
  p_member_id uuid,
  p_added_by  text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  m            record;
  v_adder      text;
  v_msg        text;
  v_person     uuid;
  v_age        integer;
  v_parent_ph  text;
  v_parent_pid uuid;
begin
  select fm.*, f.family_name, f.phone as family_phone into m
  from public.family_members fm
  join public.families f on f.id = fm.family_id
  where fm.id = p_member_id;

  if not found then return false; end if;
  if m.phone is null or btrim(m.phone) = ''        then return false; end if;
  if coalesce(m.receives_sms, true) = false        then return false; end if;
  if m.sms_status in ('confirmed','declined','pending','awaiting_parent')
                                                    then return false; end if;

  v_adder := coalesce(
    p_added_by,
    (select p.display_name from public.people p
       join public.family_access fa on fa.person_id = p.id
      where fa.family_id = m.family_id and fa.role='owner' limit 1),
    'Someone');

  v_age := public.member_age(p_member_id);

  ------------------------------------------------------------------
  -- MINOR UNDER 13 -> ask the parent, on the parent's phone.
  ------------------------------------------------------------------
  if v_age is not null and v_age < 13 then
    select p.id, p.phone into v_parent_pid, v_parent_ph
    from public.people p
    join public.family_access fa on fa.person_id = p.id
    where fa.family_id = m.family_id and fa.role='owner' and fa.status='active'
    limit 1;

    v_parent_ph := coalesce(v_parent_ph, m.family_phone);
    if v_parent_ph is null then return false; end if;

    v_msg := 'HomeHuddle: ' || v_adder || ' added ' || coalesce(m.name,'a child')
             || ' at ' || public.format_phone_display(m.phone)
             || ' to receive game reminders. Reply YES to confirm this number, STOP to cancel.';

    insert into public.sms_outbox
      (person_id, phone, family_id, event_ref, change_hash, message, status)
    values (v_parent_pid, v_parent_ph, m.family_id,
            'confirm-minor:' || p_member_id::text, md5(v_msg), v_msg, 'pending')
    on conflict do nothing;

    update public.family_members
       set sms_status = 'awaiting_parent', sms_confirm_sent_at = now()
     where id = p_member_id;

    return true;
  end if;

  ------------------------------------------------------------------
  -- 13+ and adults -> unchanged, to the member's own phone.
  ------------------------------------------------------------------
  v_msg := 'HomeHuddle: ' || v_adder || ' added you to the ' || m.family_name ||
           ' sports calendar. Reply YES to get game reminders, STOP to opt out.';

  select id into v_person from public.people where phone = m.phone limit 1;

  insert into public.sms_outbox
    (person_id, phone, family_id, event_ref, change_hash, message, status)
  values (v_person, m.phone, m.family_id,
          'confirm:' || p_member_id::text, md5(v_msg), v_msg, 'pending')
  on conflict do nothing;

  update public.family_members
     set sms_status = 'pending', sms_confirm_sent_at = now()
   where id = p_member_id;

  return true;
end;
$$;

-- Once a parent confirms, the child's first message is a notice (not a request),
-- carrying opt-out instructions as A2P practice requires.
create or replace function public.trg_minor_confirmed_notice()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_msg text; v_fam text;
begin
  if old.sms_status = 'awaiting_parent' and new.sms_status = 'confirmed' then
    select family_name into v_fam from public.families where id = new.family_id;
    v_msg := 'HomeHuddle: You''ll now get game reminders for the ' || coalesce(v_fam,'family')
             || ' calendar the night before. Reply STOP to opt out.';
    begin
      insert into public.sms_outbox (person_id, phone, family_id, event_ref, change_hash, message, status)
      values (new.person_id, new.phone, new.family_id,
              'minor-notice:' || new.id::text, md5(v_msg), v_msg, 'pending')
      on conflict do nothing;
    exception when others then null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists minor_confirmed_notice on public.family_members;
create trigger minor_confirmed_notice
  after update of sms_status on public.family_members
  for each row execute function public.trg_minor_confirmed_notice();

-- 1) consent state on the roster
alter table public.family_members
  add column if not exists sms_status text not null default 'none',
  add column if not exists sms_confirm_sent_at timestamptz;

-- 2) invite RPC: adults get a one-time confirmation text; players never auto-send.
create or replace function public.invite_family_member(
  p_family_id uuid,
  p_phone     text,
  p_name      text default null,
  p_role      text default 'viewer',
  p_can_edit  boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_caller_person uuid;
  v_owner_name    text;
  v_family_name   text;
  v_authorized    boolean;
  v_phone         text;
  v_digits        text;
  v_existing      uuid;
  v_person_id     uuid;
  v_person_verified boolean := false;
  v_linked        boolean := false;
  v_sms_status    text := 'none';
  v_msg           text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  v_digits := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
  if length(v_digits) = 10 then v_phone := '+1' || v_digits;
  elsif length(v_digits) = 11 and left(v_digits,1)='1' then v_phone := '+' || v_digits;
  elsif left(coalesce(p_phone,''),1)='+' then v_phone := trim(p_phone);
  else v_phone := null; end if;
  if v_phone is null or v_phone !~ '^\+[1-9]\d{6,14}$' then
    raise exception 'invalid phone number: %', p_phone;
  end if;

  select p.id, p.display_name into v_caller_person, v_owner_name
  from public.people p where p.auth_user_id = auth.uid() limit 1;
  if v_caller_person is null then raise exception 'caller has no person record'; end if;

  select exists(
    select 1 from public.family_access fa
    where fa.person_id = v_caller_person and fa.family_id = p_family_id
      and fa.status='active' and (fa.role='owner' or fa.can_edit=true)
  ) into v_authorized;
  if not v_authorized then raise exception 'not authorized to invite to this family'; end if;

  if p_role not in ('parent','grandparent','viewer','player') then p_role := 'viewer'; end if;
  select family_name into v_family_name from public.families where id = p_family_id;

  -- does a verified person already exist for this phone? (they consented by logging in)
  select id, coalesce(phone_verified,false) into v_person_id, v_person_verified
  from public.people where phone = v_phone limit 1;

  -- decide consent state for this member
  if p_role = 'player' then
    v_sms_status := 'none';                 -- minors: never auto-send; parent opts in later
  elsif v_person_id is not null and v_person_verified then
    v_sms_status := 'confirmed';            -- already opted in by logging in
  else
    v_sms_status := 'pending';              -- adult, not yet opted in -> send confirmation
  end if;

  -- upsert roster row (idempotent; no unique constraint)
  select id into v_existing from public.family_members
  where family_id = p_family_id and phone = v_phone limit 1;

  if v_existing is null then
    insert into public.family_members
      (family_id, name, role, phone, receives_sms, receives_push,
       can_add_events, can_edit_events, is_owner, sms_status,
       sms_confirm_sent_at)
    values
      (p_family_id, coalesce(nullif(trim(p_name),''),'Family member'),
       p_role, v_phone, true, true, p_can_edit, false, false, v_sms_status,
       case when v_sms_status='pending' then now() else null end)
    returning id into v_existing;
  else
    update public.family_members
      set name = coalesce(nullif(trim(p_name),''), name),
          role = p_role,
          can_add_events = p_can_edit,
          -- only advance status to pending/confirmed; never clobber an existing decision
          sms_status = case
            when sms_status in ('confirmed','declined','pending') then sms_status
            else v_sms_status end,
          sms_confirm_sent_at = case
            when sms_status = 'none' and v_sms_status = 'pending' then now()
            else sms_confirm_sent_at end
      where id = v_existing;
    select sms_status into v_sms_status from public.family_members where id = v_existing;
  end if;

  -- link calendar access immediately if a person already exists
  if v_person_id is not null then
    insert into public.family_access (person_id, family_id, role, status, can_edit)
    values (v_person_id, p_family_id, p_role, 'active', p_can_edit)
    on conflict (person_id, family_id) do nothing;
    update public.family_members set person_id = v_person_id
      where family_id = p_family_id and phone = v_phone and person_id is distinct from v_person_id;
    v_linked := true;
  end if;

  -- queue the one-time confirmation text for a pending adult
  if v_sms_status = 'pending' then
    v_msg := 'HomeHuddle: ' || coalesce(v_owner_name,'A family member')
          || ' added you to the ' || coalesce(v_family_name,'family')
          || ' sports calendar. Reply YES to get game reminders, STOP to opt out.';
    insert into public.sms_outbox (person_id, phone, family_id, event_ref, change_hash, message, status)
    values (v_person_id, v_phone, p_family_id,
            'confirm:' || p_family_id::text || ':' || v_phone,
            md5(v_msg), v_msg, 'pending')
    on conflict (person_id, event_ref, change_hash) do nothing;
  end if;

  return jsonb_build_object('ok', true, 'phone', v_phone, 'family_id', p_family_id,
    'role', p_role, 'already_linked', v_linked, 'sms_status', v_sms_status);
end;
$$;

revoke all on function public.invite_family_member(uuid,text,text,text,boolean) from public, anon;
grant execute on function public.invite_family_member(uuid,text,text,text,boolean) to authenticated;

-- 3) parent-initiated opt-in for a player (minor)
create or replace function public.request_player_sms(p_family_id uuid, p_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_caller_person uuid;
  v_authorized boolean;
  v_m record;
  v_family_name text;
  v_owner_name text;
  v_msg text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select p.id, p.display_name into v_caller_person, v_owner_name
  from public.people p where p.auth_user_id = auth.uid() limit 1;
  if v_caller_person is null then raise exception 'caller has no person record'; end if;

  select exists(
    select 1 from public.family_access fa
    where fa.person_id = v_caller_person and fa.family_id = p_family_id
      and fa.status='active' and (fa.role='owner' or fa.can_edit=true)
  ) into v_authorized;
  if not v_authorized then raise exception 'not authorized'; end if;

  select * into v_m from public.family_members
  where id = p_member_id and family_id = p_family_id limit 1;
  if v_m.id is null then raise exception 'member not found'; end if;
  if v_m.phone is null then raise exception 'member has no phone'; end if;
  if v_m.sms_status = 'confirmed' then
    return jsonb_build_object('ok', true, 'already', true, 'sms_status','confirmed');
  end if;

  select family_name into v_family_name from public.families where id = p_family_id;

  update public.family_members
    set sms_status = 'pending', sms_confirm_sent_at = now()
    where id = p_member_id;

  v_msg := 'HomeHuddle: ' || coalesce(v_owner_name,'A parent')
        || ' added this number to the ' || coalesce(v_family_name,'family')
        || ' sports calendar for ' || coalesce(v_m.name,'a player')
        || '. Reply YES to get game reminders, STOP to opt out.';
  insert into public.sms_outbox (person_id, phone, family_id, event_ref, change_hash, message, status)
  values (v_m.person_id, v_m.phone, p_family_id,
          'confirm:' || p_family_id::text || ':' || v_m.phone,
          md5(v_msg), v_msg, 'pending')
  on conflict (person_id, event_ref, change_hash) do nothing;

  return jsonb_build_object('ok', true, 'sms_status','pending');
end;
$$;

revoke all on function public.request_player_sms(uuid,uuid) from public, anon;
grant execute on function public.request_player_sms(uuid,uuid) to authenticated;

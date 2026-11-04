
-- Owner-authorized, phone-bound family invite.
-- Security: family_id is validated against the CALLER's own active owner/editor
-- access. An invitee can never call this for a family they don't own/edit.
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
  v_authorized    boolean;
  v_phone         text;
  v_digits        text;
  v_existing      uuid;
  v_person_id     uuid;
  v_linked        boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- normalize + validate phone to E.164 (US-friendly)
  v_digits := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
  if length(v_digits) = 10 then
    v_phone := '+1' || v_digits;
  elsif length(v_digits) = 11 and left(v_digits,1) = '1' then
    v_phone := '+' || v_digits;
  elsif left(coalesce(p_phone,''),1) = '+' then
    v_phone := trim(p_phone);
  else
    v_phone := null;
  end if;
  if v_phone is null or v_phone !~ '^\+[1-9]\d{6,14}$' then
    raise exception 'invalid phone number: %', p_phone;
  end if;

  -- AUTHORIZATION: caller must be an active owner/editor of THIS family
  select p.id into v_caller_person
  from public.people p
  where p.auth_user_id = auth.uid()
  limit 1;
  if v_caller_person is null then
    raise exception 'caller has no person record';
  end if;

  select exists(
    select 1 from public.family_access fa
    where fa.person_id = v_caller_person
      and fa.family_id = p_family_id
      and fa.status = 'active'
      and (fa.role = 'owner' or fa.can_edit = true)
  ) into v_authorized;
  if not v_authorized then
    raise exception 'not authorized to invite to this family';
  end if;

  -- sanitize role; never grant owner via invite
  if p_role not in ('parent','grandparent','viewer','player') then
    p_role := 'viewer';
  end if;

  -- add to the family_members allow-list (idempotent; no unique constraint exists)
  select id into v_existing
  from public.family_members
  where family_id = p_family_id and phone = v_phone
  limit 1;

  if v_existing is null then
    insert into public.family_members
      (family_id, name, role, phone, receives_sms, receives_push,
       can_add_events, can_edit_events, is_owner)
    values
      (p_family_id, coalesce(nullif(trim(p_name),''),'Family member'),
       p_role, v_phone, true, true, p_can_edit, false, false);
  else
    update public.family_members
      set name = coalesce(nullif(trim(p_name),''), name),
          role = p_role,
          can_add_events = p_can_edit
    where id = v_existing;
  end if;

  -- if this phone already belongs to a (verified) person, link immediately
  select id into v_person_id from public.people where phone = v_phone limit 1;
  if v_person_id is not null then
    insert into public.family_access (person_id, family_id, role, status, can_edit)
    values (v_person_id, p_family_id, p_role, 'active', p_can_edit)
    on conflict (person_id, family_id) do nothing;
    update public.family_members
      set person_id = v_person_id
      where family_id = p_family_id and phone = v_phone
        and person_id is distinct from v_person_id;
    v_linked := true;
  end if;

  return jsonb_build_object(
    'ok', true, 'phone', v_phone, 'family_id', p_family_id,
    'role', p_role, 'already_linked', v_linked
  );
end;
$$;

revoke all on function public.invite_family_member(uuid,text,text,text,boolean) from public;
revoke all on function public.invite_family_member(uuid,text,text,text,boolean) from anon;
grant execute on function public.invite_family_member(uuid,text,text,text,boolean) to authenticated;

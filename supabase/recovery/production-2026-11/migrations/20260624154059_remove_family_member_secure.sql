
create or replace function public.remove_family_member(
  p_family_id uuid,
  p_member_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_caller_person uuid;
  v_authorized    boolean;
  v_member        record;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- caller must be an active owner/editor of this family
  select p.id into v_caller_person
  from public.people p where p.auth_user_id = auth.uid() limit 1;
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
    raise exception 'not authorized to manage this family';
  end if;

  -- the target must belong to THIS family
  select * into v_member
  from public.family_members
  where id = p_member_id and family_id = p_family_id
  limit 1;
  if v_member.id is null then
    raise exception 'member not found in this family';
  end if;

  -- never remove the family owner
  if coalesce(v_member.is_owner, false) then
    raise exception 'cannot remove the family owner';
  end if;

  -- revoke calendar access for this person in THIS family (by link or phone), never the owner
  delete from public.family_access fa
  using public.people pp
  where fa.person_id = pp.id
    and fa.family_id = p_family_id
    and fa.role <> 'owner'
    and (pp.id = v_member.person_id or pp.phone = v_member.phone);

  -- remove from the roster / allow-list
  delete from public.family_members
  where id = p_member_id and family_id = p_family_id
    and coalesce(is_owner, false) = false;

  return jsonb_build_object('ok', true, 'removed_member_id', p_member_id, 'family_id', p_family_id);
end;
$$;

revoke all on function public.remove_family_member(uuid,uuid) from public;
revoke all on function public.remove_family_member(uuid,uuid) from anon;
grant execute on function public.remove_family_member(uuid,uuid) to authenticated;

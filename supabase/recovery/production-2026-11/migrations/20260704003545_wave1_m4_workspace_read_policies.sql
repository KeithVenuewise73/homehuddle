begin;

create or replace function public.current_person_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select id from public.people where auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.current_workspace_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select wm.workspace_id
  from public.workspace_members wm
  where wm.person_id = public.current_person_id()
    and wm.status = 'active';
$$;

create or replace function public.visible_workspace_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select b.id
  from public.business_workspaces b
  where b.id in (select public.current_workspace_ids())
     or b.parent_workspace_id in (select public.current_workspace_ids());
$$;

create policy wm_select_self on public.workspace_members
  for select to authenticated
  using (person_id = public.current_person_id());

create policy wr_select_self on public.workspace_roles
  for select to authenticated
  using (person_id = public.current_person_id());

create policy bw_select_visible on public.business_workspaces
  for select to authenticated
  using (id in (select public.visible_workspace_ids()));

create policy wb_select_visible on public.workspace_branding
  for select to authenticated
  using (workspace_id in (select public.visible_workspace_ids()));

commit;
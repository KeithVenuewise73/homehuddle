begin;

insert into public.workspace_members (workspace_id, person_id, status)
select w.id, '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid, 'active'
from public.business_workspaces w
where w.slug in ('venuewise','homehuddle','ddh','ddh-athlete-development','ddh-home-services')
on conflict (workspace_id, person_id) do nothing;

insert into public.workspace_roles (workspace_id, person_id, role)
select w.id, '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid, 'owner'
from public.business_workspaces w
where w.slug in ('venuewise','homehuddle','ddh','ddh-athlete-development','ddh-home-services')
on conflict (workspace_id, person_id, role) do nothing;

commit;
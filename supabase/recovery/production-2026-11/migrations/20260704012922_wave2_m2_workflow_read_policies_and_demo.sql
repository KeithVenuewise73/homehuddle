begin;

create or replace function public.readable_workflow_template_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select id from public.workflow_templates
  where (workspace_id is null and status = 'published')
     or workspace_id in (select public.current_workspace_ids());
$$;

create policy wt_select on public.workflow_templates
  for select to authenticated
  using (id in (select public.readable_workflow_template_ids()));

create policy wts_select on public.workflow_template_stages
  for select to authenticated
  using (template_id in (select public.readable_workflow_template_ids()));

create policy wtt_select on public.workflow_template_tasks
  for select to authenticated
  using (template_id in (select public.readable_workflow_template_ids()));

create policy wi_select on public.workflow_instances
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

create policy wis_select on public.workflow_instance_stages
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

create policy wtask_select on public.workflow_tasks
  for select to authenticated
  using (
    workspace_id in (select public.current_workspace_ids())
    or assignee_person_id = public.current_person_id()
  );

create policy wa_select on public.workflow_approvals
  for select to authenticated
  using (
    workspace_id in (select public.current_workspace_ids())
    or approver_person_id = public.current_person_id()
  );

create policy we_select on public.workflow_events
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

with ws as (select id from public.business_workspaces where slug = 'venuewise'),
keith as (select '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid as pid),
tmpl as (
  insert into public.workflow_templates
    (workspace_id, industry_pack, key, name, description, subject_type, version, status, created_by)
  select ws.id, 'generic', 'demo_read_check', 'Demo — Read Path Check',
         'Throwaway template to prove the workflow read path. Safe to delete.',
         'demo', 1, 'published', keith.pid
  from ws, keith
  returning id, workspace_id
),
stage as (
  insert into public.workflow_template_stages (template_id, key, name, position)
  select id, 'review', 'Review', 0 from tmpl
  returning id, template_id
),
ttask as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, required, position)
  select stage.template_id, stage.id, 'say_hello', 'Confirm read path works', 'manual', true, 0
  from stage
  returning id
),
inst as (
  insert into public.workflow_instances
    (workspace_id, template_id, template_version, subject_type, subject_id, title, status, started_by)
  select tmpl.workspace_id, tmpl.id, 1, 'demo', null, 'Demo read-path instance', 'active', keith.pid
  from tmpl, keith
  returning id, workspace_id
),
istage as (
  insert into public.workflow_instance_stages
    (instance_id, workspace_id, template_stage_id, key, name, position, status, entered_at)
  select inst.id, inst.workspace_id, stage.id, 'review', 'Review', 0, 'active', now()
  from inst, stage
  returning id, instance_id, workspace_id
),
upd as (
  update public.workflow_instances
  set current_stage_id = istage.id
  from istage
  where public.workflow_instances.id = istage.instance_id
  returning public.workflow_instances.id
),
itask as (
  insert into public.workflow_tasks
    (instance_id, instance_stage_id, template_task_id, workspace_id, key, name,
     task_type, status, assignee_person_id, required)
  select istage.instance_id, istage.id, ttask.id, istage.workspace_id, 'say_hello',
         'Confirm read path works', 'manual', 'pending', keith.pid, true
  from istage, ttask, keith
  returning id, instance_id, workspace_id
)
insert into public.workflow_events (instance_id, workspace_id, event_type, actor_person_id, payload)
select itask.instance_id, itask.workspace_id, 'instance_started', keith.pid,
       jsonb_build_object('demo', true, 'note', 'W2M2 read-path proof')
from itask, keith;

commit;
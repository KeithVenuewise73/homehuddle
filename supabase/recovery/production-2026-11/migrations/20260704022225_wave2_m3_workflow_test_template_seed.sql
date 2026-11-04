begin;

with ws as (select id from public.business_workspaces where slug = 'venuewise'),
keith as (select '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid as pid),
tmpl as (
  insert into public.workflow_templates
    (workspace_id, industry_pack, key, name, description, subject_type, version, status, created_by)
  select ws.id, 'generic', 'orchestrator_test', 'Orchestrator Test',
         'Throwaway 3-stage template to prove wf_start / wf_advance / wf_task_action. Safe to delete.',
         'test', 1, 'published', keith.pid
  from ws, keith
  returning id
),
s1 as (
  insert into public.workflow_template_stages (template_id, key, name, position, advance_rule)
  select id, 'intake', 'Intake', 0, '{"when":"all_required_tasks_complete"}'::jsonb from tmpl
  returning id, template_id
),
s2 as (
  insert into public.workflow_template_stages (template_id, key, name, position, advance_rule)
  select template_id, 'review', 'Review', 1, '{"when":"approval","task_key":"manager_ok"}'::jsonb from s1
  returning id, template_id
),
s3 as (
  insert into public.workflow_template_stages (template_id, key, name, position, advance_rule)
  select template_id, 'closeout', 'Closeout', 2, '{"when":"all_required_tasks_complete"}'::jsonb from s2
  returning id, template_id
),
t1 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
  select s1.template_id, s1.id, 'fill_form', 'Fill intake form', 'manual',
         '{"role":"owner"}'::jsonb, true, 0 from s1
  returning id
),
t2 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, config, required, position)
  select s2.template_id, s2.id, 'manager_ok', 'Manager approval', 'approval',
         '{"role":"owner"}'::jsonb, '{"required_role":"owner"}'::jsonb, true, 0 from s2
  returning id
)
insert into public.workflow_template_tasks
  (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
select s3.template_id, s3.id, 'wrap_up', 'Wrap up', 'manual', '{"role":"owner"}'::jsonb, true, 0 from s3;

commit;
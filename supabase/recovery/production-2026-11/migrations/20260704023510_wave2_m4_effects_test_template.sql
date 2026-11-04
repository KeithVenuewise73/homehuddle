begin;

with ws as (select id from public.business_workspaces where slug='venuewise'),
keith as (select '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid as pid),
tmpl as (
  insert into public.workflow_templates
    (workspace_id, industry_pack, key, name, description, subject_type, version, status, created_by)
  select ws.id, 'generic', 'effects_test', 'Effects Test',
         'Throwaway template to prove calendar + notification effects. Safe to delete.',
         'test', 1, 'published', keith.pid
  from ws, keith
  returning id
),
s1 as (
  insert into public.workflow_template_stages (template_id, key, name, position, advance_rule)
  select id, 'schedule', 'Schedule', 0, '{"when":"all_required_tasks_complete"}'::jsonb from tmpl
  returning id, template_id
),
s2 as (
  insert into public.workflow_template_stages (template_id, key, name, position, advance_rule)
  select template_id, 'done', 'Done', 1, '{"when":"all_required_tasks_complete"}'::jsonb from s1
  returning id, template_id
),
c1 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, config, required, position)
  select s1.template_id, s1.id, 'put_on_calendar', 'Put on calendar', 'calendar',
         '{}'::jsonb,
         '{"title":"Workflow scheduled event","start_offset_days":1,"duration_minutes":60,"description":"Created by the workflow engine (test)."}'::jsonb,
         true, 0 from s1
  returning id
),
n1 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, config, required, position)
  select s1.template_id, s1.id, 'notify_owner', 'Notify owner', 'notification',
         '{"role":"owner"}'::jsonb,
         '{"message":"Your test workflow has started.","dry_run":true}'::jsonb,
         true, 1 from s1
  returning id
)
insert into public.workflow_template_tasks
  (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
select s2.template_id, s2.id, 'confirm', 'Confirm', 'manual', '{"role":"owner"}'::jsonb, true, 0 from s2;

commit;
begin;

with ws as (select id from public.business_workspaces where slug='venuewise'),
keith as (select '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid as pid),
tmpl as (
  insert into public.workflow_templates
    (workspace_id, industry_pack, key, name, description, subject_type, version, status, created_by)
  select ws.id, 'generic', 'form_sandbox_test', 'Form Sandbox Test',
         'Throwaway workflow with a form task, to prove the Forms Engine end-to-end.',
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
  select template_id, 'done', 'Done', 1, '{"when":"all_required_tasks_complete"}'::jsonb from s1
  returning id, template_id
)
insert into public.workflow_template_tasks
  (template_id, stage_id, key, name, task_type, assignee_rule, config, required, position)
select s1.template_id, s1.id, 'intake_form', 'Complete intake form', 'form',
       '{"role":"owner"}'::jsonb, '{"form_key":"demo_intake"}'::jsonb, true, 0 from s1;

commit;
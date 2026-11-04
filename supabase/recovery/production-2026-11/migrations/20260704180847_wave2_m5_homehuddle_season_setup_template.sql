begin;

with ws as (select id from public.business_workspaces where slug='homehuddle'),
keith as (select '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid as pid),
tmpl as (
  insert into public.workflow_templates
    (workspace_id, industry_pack, key, name, description, subject_type, version, status, created_by)
  select ws.id, 'sports', 'season_setup', 'Season Setup Checklist',
         'A short checklist to get a family set up for the season.',
         'family', 1, 'published', keith.pid
  from ws, keith
  returning id
),
stage as (
  insert into public.workflow_template_stages (template_id, key, name, position, advance_rule)
  select id, 'setup', 'Setup', 0, '{"when":"all_required_tasks_complete"}'::jsonb from tmpl
  returning id, template_id
),
t1 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
  select stage.template_id, stage.id, 'confirm_profile', 'Confirm family profile', 'manual',
         '{"role":"owner"}'::jsonb, true, 0 from stage
  returning id
),
t2 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
  select stage.template_id, stage.id, 'confirm_athletes', 'Confirm athletes / children', 'manual',
         '{"role":"owner"}'::jsonb, true, 1 from stage
  returning id
),
t3 as (
  insert into public.workflow_template_tasks
    (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
  select stage.template_id, stage.id, 'confirm_feeds', 'Confirm calendar feeds', 'manual',
         '{"role":"owner"}'::jsonb, true, 2 from stage
  returning id
)
insert into public.workflow_template_tasks
  (template_id, stage_id, key, name, task_type, assignee_rule, required, position)
select stage.template_id, stage.id, 'review_schedule', 'Review upcoming schedule', 'manual',
       '{"role":"owner"}'::jsonb, true, 3 from stage;

commit;
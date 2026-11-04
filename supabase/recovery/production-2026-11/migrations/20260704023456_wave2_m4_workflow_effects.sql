begin;

alter table public.calendar_events drop constraint calendar_events_source_module_check;
alter table public.calendar_events add constraint calendar_events_source_module_check
  check (source_module = any (array[
    'homehuddle','athletehuddle','coacheshuddle','organizationhuddle',
    'facilityhuddle','tournamenthuddle','workflow'
  ]));

create or replace function public.wf_effect_calendar(p_task_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_task record; v_cfg jsonb; v_title text; v_start timestamptz; v_end timestamptz; v_cal_id uuid;
begin
  select * into v_task from public.workflow_tasks where id = p_task_id;
  v_cfg := coalesce(v_task.config, '{}'::jsonb);
  v_title := coalesce(v_cfg->>'title', v_task.name);
  v_start := coalesce(
    (v_cfg->>'start_at')::timestamptz,
    case when v_cfg ? 'start_offset_days'
         then now() + ((v_cfg->>'start_offset_days') || ' days')::interval end,
    v_task.due_at, now());
  v_end := case
    when v_cfg ? 'end_at' then (v_cfg->>'end_at')::timestamptz
    when v_cfg ? 'duration_minutes' then v_start + ((v_cfg->>'duration_minutes') || ' minutes')::interval
    else null end;

  insert into public.calendar_events
    (source_module, source_table, source_id, title, description, event_type,
     start_time, end_time, workspace_id, status)
  values ('workflow', 'workflow_tasks', p_task_id::text, v_title, v_cfg->>'description', 'workflow',
          v_start, v_end, v_task.workspace_id, 'active')
  returning id into v_cal_id;

  update public.workflow_tasks
    set status='complete', completed_at=now(), completed_by=p_actor,
        effect_ref = jsonb_build_object('calendar_event_id', v_cal_id), updated_at=now()
    where id = p_task_id;

  insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
  values (v_task.instance_id, p_task_id, v_task.workspace_id, 'effect_dispatched', p_actor,
          jsonb_build_object('effect','calendar','calendar_event_id',v_cal_id,'title',v_title,'start_time',v_start));
end;
$$;

create or replace function public.wf_effect_notification(p_task_id uuid, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_task record; v_cfg jsonb; v_person uuid; v_phone text; v_msg text; v_dry boolean;
begin
  select * into v_task from public.workflow_tasks where id = p_task_id;
  v_cfg := coalesce(v_task.config, '{}'::jsonb);
  v_dry := coalesce((v_cfg->>'dry_run')::boolean, true);

  if v_cfg ? 'recipient_person_id' then v_person := (v_cfg->>'recipient_person_id')::uuid;
  else v_person := v_task.assignee_person_id; end if;
  select phone into v_phone from public.people where id = v_person;
  v_msg := coalesce(v_cfg->>'message', v_task.name);

  update public.workflow_tasks
    set status='complete', completed_at=now(), completed_by=p_actor,
        effect_ref = jsonb_build_object('notification','dry_run','to_person',v_person), updated_at=now()
    where id = p_task_id;

  insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
  values (v_task.instance_id, p_task_id, v_task.workspace_id, 'effect_dispatched', p_actor,
          jsonb_build_object('effect','notification','channel','sms','dry_run',v_dry,
                             'to_person',v_person,'to_phone',v_phone,'message',v_msg));
end;
$$;

create or replace function public.wf_generate_stage_tasks(
  p_instance_id uuid, p_instance_stage_id uuid, p_template_stage_id uuid, p_actor uuid
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_ws uuid; v_entered timestamptz; rec record; v_assignee uuid; v_role text;
  v_due timestamptz; v_task_id uuid; v_req_role text;
begin
  select workspace_id into v_ws from public.workflow_instances where id = p_instance_id;
  select coalesce(entered_at, now()) into v_entered
    from public.workflow_instance_stages where id = p_instance_stage_id;

  for rec in
    select * from public.workflow_template_tasks
    where stage_id = p_template_stage_id order by position, created_at
  loop
    v_assignee := null; v_role := null;
    if rec.assignee_rule ? 'person_id' then
      v_assignee := (rec.assignee_rule->>'person_id')::uuid;
    elsif rec.assignee_rule ? 'role' then
      v_role := rec.assignee_rule->>'role';
      select person_id into v_assignee from public.workspace_roles
        where workspace_id = v_ws and role = v_role limit 1;
    end if;

    v_due := case when rec.due_offset_days is not null
                  then v_entered + (rec.due_offset_days || ' days')::interval else null end;

    insert into public.workflow_tasks
      (instance_id, instance_stage_id, template_task_id, workspace_id, key, name,
       task_type, status, assignee_person_id, assignee_role, due_at, required, config)
    values
      (p_instance_id, p_instance_stage_id, rec.id, v_ws, rec.key, rec.name,
       rec.task_type, 'pending', v_assignee, v_role, v_due, rec.required, rec.config)
    returning id into v_task_id;

    insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
    values (p_instance_id, v_task_id, v_ws, 'task_created', p_actor,
            jsonb_build_object('key', rec.key, 'task_type', rec.task_type));

    if rec.task_type = 'approval' then
      v_req_role := coalesce(rec.config->>'required_role', v_role);
      insert into public.workflow_approvals (task_id, instance_id, workspace_id, required_role, decision)
      values (v_task_id, p_instance_id, v_ws, v_req_role, 'pending');
    elsif rec.task_type = 'calendar' then
      perform public.wf_effect_calendar(v_task_id, p_actor);
    elsif rec.task_type = 'notification' then
      perform public.wf_effect_notification(v_task_id, p_actor);
    end if;
  end loop;
end;
$$;

create or replace function public.wf_tick()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_reminders int := 0; v_processed int := 0; rec record;
begin
  for rec in
    select t.* from public.workflow_tasks t
    join public.workflow_instances i on i.id = t.instance_id
    where i.status='active' and t.status='pending'
      and t.due_at is not null and t.due_at < now()
      and t.task_type in ('manual','approval')
  loop
    insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
    values (rec.instance_id, rec.id, rec.workspace_id, 'reminder_due', null,
            jsonb_build_object('dry_run', true, 'task', rec.key, 'due_at', rec.due_at));
    v_reminders := v_reminders + 1;
  end loop;

  for rec in select id from public.workflow_instances where status='active' loop
    perform public.wf_advance(rec.id, null);
    v_processed := v_processed + 1;
  end loop;

  return jsonb_build_object('reminders', v_reminders, 'instances_processed', v_processed);
end;
$$;

revoke all on function
  public.wf_effect_calendar(uuid,uuid),
  public.wf_effect_notification(uuid,uuid),
  public.wf_tick()
from public, anon, authenticated;
grant execute on function
  public.wf_effect_calendar(uuid,uuid),
  public.wf_effect_notification(uuid,uuid),
  public.wf_tick()
to service_role;

commit;
begin;

create or replace function public.wf_is_member(p_person uuid, p_workspace uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.workspace_members
    where person_id = p_person and workspace_id = p_workspace and status = 'active'
  );
$$;

create or replace function public.wf_has_role(p_person uuid, p_workspace uuid, p_role text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.workspace_roles
    where person_id = p_person and workspace_id = p_workspace and role = p_role
  );
$$;

create or replace function public.wf_generate_stage_tasks(
  p_instance_id uuid, p_instance_stage_id uuid, p_template_stage_id uuid, p_actor uuid
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_ws        uuid;
  v_entered   timestamptz;
  rec         record;
  v_assignee  uuid;
  v_role      text;
  v_due       timestamptz;
  v_task_id   uuid;
  v_req_role  text;
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

    if rec.task_type = 'approval' then
      v_req_role := coalesce(rec.config->>'required_role', v_role);
      insert into public.workflow_approvals
        (task_id, instance_id, workspace_id, required_role, decision)
      values (v_task_id, p_instance_id, v_ws, v_req_role, 'pending');
    end if;

    insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
    values (p_instance_id, v_task_id, v_ws, 'task_created', p_actor,
            jsonb_build_object('key', rec.key, 'task_type', rec.task_type));
  end loop;
end;
$$;

create or replace function public.wf_start(
  p_template_id uuid, p_workspace_id uuid, p_subject_type text, p_subject_id text,
  p_title text, p_context jsonb, p_actor uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_tmpl        record;
  v_instance_id uuid;
  v_stage       record;
  v_inst_stage  uuid;
begin
  if not public.wf_is_member(p_actor, p_workspace_id) then
    raise exception 'not authorized: actor is not a member of the workspace';
  end if;

  select * into v_tmpl from public.workflow_templates where id = p_template_id;
  if v_tmpl is null or v_tmpl.status <> 'published' then
    raise exception 'template not found or not published';
  end if;

  insert into public.workflow_instances
    (workspace_id, template_id, template_version, subject_type, subject_id, title,
     status, context, started_by)
  values
    (p_workspace_id, p_template_id, v_tmpl.version, p_subject_type, p_subject_id,
     coalesce(p_title, v_tmpl.name), 'active', coalesce(p_context, '{}'::jsonb), p_actor)
  returning id into v_instance_id;

  insert into public.workflow_events (instance_id, workspace_id, event_type, actor_person_id, payload)
  values (v_instance_id, p_workspace_id, 'instance_started', p_actor,
          jsonb_build_object('template', v_tmpl.key, 'subject_type', p_subject_type));

  select * into v_stage from public.workflow_template_stages
    where template_id = p_template_id order by position limit 1;
  if v_stage is null then
    update public.workflow_instances set status='completed', completed_at=now(), updated_at=now()
      where id = v_instance_id;
    return v_instance_id;
  end if;

  insert into public.workflow_instance_stages
    (instance_id, workspace_id, template_stage_id, key, name, position, status, entered_at)
  values (v_instance_id, p_workspace_id, v_stage.id, v_stage.key, v_stage.name, v_stage.position, 'active', now())
  returning id into v_inst_stage;

  update public.workflow_instances set current_stage_id = v_inst_stage, updated_at = now()
    where id = v_instance_id;

  insert into public.workflow_events (instance_id, workspace_id, event_type, actor_person_id, payload)
  values (v_instance_id, p_workspace_id, 'stage_entered', p_actor, jsonb_build_object('stage', v_stage.key));

  perform public.wf_generate_stage_tasks(v_instance_id, v_inst_stage, v_stage.id, p_actor);
  perform public.wf_advance(v_instance_id, p_actor);
  return v_instance_id;
end;
$$;

create or replace function public.wf_advance(p_instance_id uuid, p_actor uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_inst        record;
  v_stage       record;
  v_tmpl_stage  record;
  v_when        text;
  v_satisfied   boolean;
  v_incomplete  int;
  v_dec         text;
  v_next        record;
  v_new_stage   uuid;
  v_guard       int := 0;
begin
  loop
    v_guard := v_guard + 1;
    if v_guard > 50 then raise exception 'wf_advance loop guard tripped'; end if;

    select * into v_inst from public.workflow_instances where id = p_instance_id;
    if v_inst is null then return 'not_found'; end if;
    if v_inst.status <> 'active' then return v_inst.status; end if;
    if v_inst.current_stage_id is null then return 'no_current_stage'; end if;

    select * into v_stage from public.workflow_instance_stages where id = v_inst.current_stage_id;
    select * into v_tmpl_stage from public.workflow_template_stages where id = v_stage.template_stage_id;

    v_when := coalesce(v_tmpl_stage.advance_rule->>'when', 'all_required_tasks_complete');
    if v_when = 'manual' then
      return 'waiting_manual';
    elsif v_when = 'approval' then
      select a.decision into v_dec
        from public.workflow_tasks t
        join public.workflow_approvals a on a.task_id = t.id
       where t.instance_stage_id = v_stage.id
         and t.key = (v_tmpl_stage.advance_rule->>'task_key')
       limit 1;
      v_satisfied := (v_dec = 'approved');
    else
      select count(*) into v_incomplete from public.workflow_tasks
        where instance_stage_id = v_stage.id and required = true
          and status not in ('complete','skipped');
      v_satisfied := (v_incomplete = 0);
    end if;

    if not v_satisfied then return 'waiting'; end if;

    update public.workflow_instance_stages
      set status='complete', completed_at=now() where id = v_stage.id;
    insert into public.workflow_events (instance_id, workspace_id, event_type, actor_person_id, payload)
      values (p_instance_id, v_inst.workspace_id, 'stage_completed', p_actor,
              jsonb_build_object('stage', v_stage.key));

    select * into v_next from public.workflow_template_stages
      where template_id = v_inst.template_id and position > v_tmpl_stage.position
      order by position limit 1;

    if v_next is null then
      update public.workflow_instances
        set status='completed', completed_at=now(), updated_at=now() where id = p_instance_id;
      insert into public.workflow_events (instance_id, workspace_id, event_type, actor_person_id, payload)
        values (p_instance_id, v_inst.workspace_id, 'instance_completed', p_actor, '{}'::jsonb);
      return 'completed';
    end if;

    insert into public.workflow_instance_stages
      (instance_id, workspace_id, template_stage_id, key, name, position, status, entered_at)
    values (p_instance_id, v_inst.workspace_id, v_next.id, v_next.key, v_next.name, v_next.position, 'active', now())
    returning id into v_new_stage;

    update public.workflow_instances set current_stage_id = v_new_stage, updated_at = now()
      where id = p_instance_id;
    insert into public.workflow_events (instance_id, workspace_id, event_type, actor_person_id, payload)
      values (p_instance_id, v_inst.workspace_id, 'stage_entered', p_actor, jsonb_build_object('stage', v_next.key));

    perform public.wf_generate_stage_tasks(p_instance_id, v_new_stage, v_next.id, p_actor);
  end loop;
end;
$$;

create or replace function public.wf_task_action(
  p_task_id uuid, p_actor uuid, p_action text, p_result jsonb, p_comment text
) returns text language plpgsql security definer set search_path = public as $$
declare
  v_task   record;
  v_ws     uuid;
  v_req    text;
  v_can    boolean;
begin
  select * into v_task from public.workflow_tasks where id = p_task_id;
  if v_task is null then raise exception 'task not found'; end if;
  v_ws := v_task.workspace_id;

  if p_action = 'complete' then
    v_can := (v_task.assignee_person_id = p_actor)
             or public.wf_has_role(p_actor, v_ws, 'owner')
             or public.wf_has_role(p_actor, v_ws, 'admin')
             or (v_task.assignee_role is not null and public.wf_has_role(p_actor, v_ws, v_task.assignee_role));
    if not v_can then raise exception 'not authorized to complete this task'; end if;
    update public.workflow_tasks
      set status='complete', completed_by=p_actor, completed_at=now(),
          result=coalesce(p_result,'{}'::jsonb), updated_at=now()
      where id = p_task_id;
    insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
      values (v_task.instance_id, p_task_id, v_ws, 'task_completed', p_actor, coalesce(p_result,'{}'::jsonb));

  elsif p_action in ('approve','reject') then
    if v_task.task_type <> 'approval' then raise exception 'task is not an approval'; end if;
    select required_role into v_req from public.workflow_approvals where task_id = p_task_id limit 1;
    v_can := (v_req is not null and public.wf_has_role(p_actor, v_ws, v_req))
             or public.wf_has_role(p_actor, v_ws, 'owner')
             or public.wf_has_role(p_actor, v_ws, 'admin');
    if not v_can then raise exception 'not authorized to decide this approval'; end if;

    update public.workflow_approvals
      set decision = case when p_action='approve' then 'approved' else 'rejected' end,
          approver_person_id = p_actor, decided_at = now(), comment = p_comment
      where task_id = p_task_id;
    update public.workflow_tasks
      set status = case when p_action='approve' then 'complete' else 'rejected' end,
          completed_by = p_actor, completed_at = now(), updated_at = now()
      where id = p_task_id;
    insert into public.workflow_events (instance_id, task_id, workspace_id, event_type, actor_person_id, payload)
      values (v_task.instance_id, p_task_id, v_ws, 'approval_decided', p_actor,
              jsonb_build_object('decision', p_action, 'comment', p_comment));
  else
    raise exception 'unknown action: %', p_action;
  end if;

  return public.wf_advance(v_task.instance_id, p_actor);
end;
$$;

revoke all on function
  public.wf_is_member(uuid,uuid),
  public.wf_has_role(uuid,uuid,text),
  public.wf_generate_stage_tasks(uuid,uuid,uuid,uuid),
  public.wf_start(uuid,uuid,text,text,text,jsonb,uuid),
  public.wf_advance(uuid,uuid),
  public.wf_task_action(uuid,uuid,text,jsonb,text)
from public, anon, authenticated;

grant execute on function
  public.wf_is_member(uuid,uuid),
  public.wf_has_role(uuid,uuid,text),
  public.wf_generate_stage_tasks(uuid,uuid,uuid,uuid),
  public.wf_start(uuid,uuid,text,text,text,jsonb,uuid),
  public.wf_advance(uuid,uuid),
  public.wf_task_action(uuid,uuid,text,jsonb,text)
to service_role;

commit;
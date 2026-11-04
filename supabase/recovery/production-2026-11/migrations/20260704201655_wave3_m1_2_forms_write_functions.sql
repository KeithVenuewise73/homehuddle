begin;

create or replace function public.fs_save_draft(
  p_submission_id uuid, p_form_template_id uuid, p_workspace_id uuid,
  p_subject_type text, p_subject_id text,
  p_workflow_instance_id uuid, p_workflow_task_id uuid,
  p_data jsonb, p_actor uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ver integer; v_sub record;
begin
  if p_submission_id is not null then
    select * into v_sub from public.form_submissions where id = p_submission_id;
    if v_sub is null then raise exception 'submission not found'; end if;
    if v_sub.status <> 'draft' then raise exception 'submission is not a draft'; end if;
    if not (v_sub.created_by = p_actor or public.wf_is_member(p_actor, v_sub.workspace_id)) then
      raise exception 'not authorized to edit this submission';
    end if;
    update public.form_submissions
      set data = coalesce(p_data, '{}'::jsonb), updated_at = now()
      where id = p_submission_id;
    insert into public.form_submission_events (submission_id, workspace_id, event_type, actor_person_id, payload)
      values (p_submission_id, v_sub.workspace_id, 'draft_saved', p_actor, '{}'::jsonb);
    return p_submission_id;
  end if;

  if not public.wf_is_member(p_actor, p_workspace_id) then
    raise exception 'not authorized: not a member of the workspace';
  end if;
  select version into v_ver from public.form_templates
    where id = p_form_template_id and status = 'published';
  if v_ver is null then raise exception 'form template not found or not published'; end if;

  insert into public.form_submissions
    (workspace_id, form_template_id, template_version, subject_type, subject_id,
     workflow_instance_id, workflow_task_id, status, data, created_by)
  values
    (p_workspace_id, p_form_template_id, v_ver, p_subject_type, p_subject_id,
     p_workflow_instance_id, p_workflow_task_id, 'draft', coalesce(p_data,'{}'::jsonb), p_actor)
  returning id into v_id;

  insert into public.form_submission_events (submission_id, workspace_id, event_type, actor_person_id, payload)
    values (v_id, p_workspace_id, 'form_started', p_actor, jsonb_build_object('template', p_form_template_id));
  insert into public.form_submission_events (submission_id, workspace_id, event_type, actor_person_id, payload)
    values (v_id, p_workspace_id, 'draft_saved', p_actor, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function public.fs_submit(
  p_submission_id uuid, p_data jsonb, p_actor uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sub record; v_missing text; v_wf_status text;
begin
  select * into v_sub from public.form_submissions where id = p_submission_id;
  if v_sub is null then raise exception 'submission not found'; end if;
  if v_sub.status <> 'draft' then raise exception 'submission already submitted'; end if;

  if not (v_sub.created_by = p_actor
          or public.wf_is_member(p_actor, v_sub.workspace_id)
          or exists (select 1 from public.workflow_tasks t
                     where t.id = v_sub.workflow_task_id and t.assignee_person_id = p_actor)) then
    raise exception 'not authorized to submit this form';
  end if;

  select f.key into v_missing
  from public.form_fields f
  join public.form_sections s on s.id = f.section_id
  where f.form_template_id = v_sub.form_template_id
    and f.required = true
    and f.visible_if = '{}'::jsonb
    and s.visible_if = '{}'::jsonb
    and s.repeatable = false
    and f.field_type not in ('info','signature','file')
    and ((p_data -> s.key ->> f.key) is null or btrim(p_data -> s.key ->> f.key) = '')
  limit 1;
  if v_missing is not null then
    raise exception 'required field missing: %', v_missing;
  end if;

  update public.form_submissions
    set data = coalesce(p_data, v_sub.data), status = 'completed',
        submitted_by = p_actor, submitted_at = now(), updated_at = now()
    where id = p_submission_id;
  insert into public.form_submission_events (submission_id, workspace_id, event_type, actor_person_id, payload)
    values (p_submission_id, v_sub.workspace_id, 'form_submitted', p_actor, '{}'::jsonb);

  if v_sub.workflow_task_id is not null then
    v_wf_status := public.wf_task_action(v_sub.workflow_task_id, p_actor, 'complete',
                     jsonb_build_object('form_submission_id', p_submission_id), null);
  end if;

  return jsonb_build_object('submission_id', p_submission_id, 'status', 'completed',
                            'workflow_status', v_wf_status);
end;
$$;

revoke all on function
  public.fs_save_draft(uuid,uuid,uuid,text,text,uuid,uuid,jsonb,uuid),
  public.fs_submit(uuid,jsonb,uuid)
from public, anon, authenticated;
grant execute on function
  public.fs_save_draft(uuid,uuid,uuid,text,text,uuid,uuid,jsonb,uuid),
  public.fs_submit(uuid,jsonb,uuid)
to service_role;

commit;
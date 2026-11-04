begin;

create or replace function public.doc_create_version(
  p_document_id uuid, p_workspace_id uuid, p_document_template_id uuid, p_template_version integer,
  p_workflow_instance_id uuid, p_workflow_task_id uuid, p_subject_type text, p_subject_id text,
  p_name text, p_storage_path text, p_file_size bigint, p_content_hash text,
  p_form_submission_id uuid, p_merge_context jsonb, p_required_role text, p_actor uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc_id uuid; v_ver integer; v_wf_status text;
begin
  if not public.wf_is_member(p_actor, p_workspace_id) then
    raise exception 'not authorized: not a member of the workspace';
  end if;

  if p_document_id is null then
    insert into public.documents
      (workspace_id, document_template_id, template_version, workflow_instance_id, workflow_task_id,
       subject_type, subject_id, name, status, current_version, generated_by)
    values
      (p_workspace_id, p_document_template_id, p_template_version, p_workflow_instance_id, p_workflow_task_id,
       p_subject_type, p_subject_id, coalesce(p_name,'Document'), 'generated', 1, p_actor)
    returning id into v_doc_id;
    v_ver := 1;
  else
    v_doc_id := p_document_id;
    select current_version + 1 into v_ver from public.documents where id = v_doc_id;
    if v_ver is null then raise exception 'document not found'; end if;
    update public.documents set current_version = v_ver, status='generated', updated_at=now() where id = v_doc_id;
  end if;

  insert into public.document_versions
    (document_id, workspace_id, version, output_format, storage_bucket, storage_path, file_size,
     content_hash, form_submission_id, merge_context, generated_by)
  values
    (v_doc_id, p_workspace_id, v_ver, 'pdf', 'documents', p_storage_path, p_file_size,
     p_content_hash, p_form_submission_id, coalesce(p_merge_context,'{}'::jsonb), p_actor);

  insert into public.document_events (document_id, workspace_id, event_type, actor_person_id, payload)
    values (v_doc_id, p_workspace_id,
            case when v_ver = 1 then 'document_generated' else 'version_created' end,
            p_actor, jsonb_build_object('version', v_ver, 'storage_path', p_storage_path));

  if p_required_role is not null then
    insert into public.document_approvals (document_id, document_version_id, workspace_id, required_role, decision)
    select v_doc_id, dv.id, p_workspace_id, p_required_role, 'pending'
    from public.document_versions dv where dv.document_id = v_doc_id and dv.version = v_ver;
    insert into public.document_events (document_id, workspace_id, event_type, actor_person_id, payload)
      values (v_doc_id, p_workspace_id, 'approval_requested', p_actor, jsonb_build_object('required_role', p_required_role));
  end if;

  if p_workflow_task_id is not null then
    v_wf_status := public.wf_task_action(p_workflow_task_id, p_actor, 'complete',
                     jsonb_build_object('document_id', v_doc_id), null);
  end if;

  return jsonb_build_object('document_id', v_doc_id, 'version', v_ver, 'workflow_status', v_wf_status);
end;
$$;

create or replace function public.doc_decide_approval(
  p_document_id uuid, p_actor uuid, p_decision text, p_comment text
) returns text language plpgsql security definer set search_path = public as $$
declare v_doc record; v_appr record; v_can boolean;
begin
  if p_decision not in ('approved','rejected') then raise exception 'invalid decision'; end if;
  select * into v_doc from public.documents where id = p_document_id;
  if v_doc is null then raise exception 'document not found'; end if;

  select * into v_appr from public.document_approvals
    where document_id = p_document_id and decision = 'pending' order by created_at desc limit 1;

  v_can := public.wf_has_role(p_actor, v_doc.workspace_id, 'owner')
           or public.wf_has_role(p_actor, v_doc.workspace_id, 'admin')
           or (v_appr.required_role is not null and public.wf_has_role(p_actor, v_doc.workspace_id, v_appr.required_role));
  if not v_can then raise exception 'not authorized to decide this document'; end if;

  if v_appr.id is not null then
    update public.document_approvals
      set decision = p_decision, approver_person_id = p_actor, decided_at = now(), comment = p_comment
      where id = v_appr.id;
  end if;
  update public.documents set status = p_decision, updated_at = now() where id = p_document_id;
  insert into public.document_events (document_id, workspace_id, event_type, actor_person_id, payload)
    values (p_document_id, v_doc.workspace_id, 'approval_decided', p_actor,
            jsonb_build_object('decision', p_decision, 'comment', p_comment));
  return p_decision;
end;
$$;

revoke all on function
  public.doc_create_version(uuid,uuid,uuid,integer,uuid,uuid,text,text,text,text,bigint,text,uuid,jsonb,text,uuid),
  public.doc_decide_approval(uuid,uuid,text,text)
from public, anon, authenticated;
grant execute on function
  public.doc_create_version(uuid,uuid,uuid,integer,uuid,uuid,text,text,text,text,bigint,text,uuid,jsonb,text,uuid),
  public.doc_decide_approval(uuid,uuid,text,text)
to service_role;

commit;
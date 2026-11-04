import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const svcKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json(401, { error: "unauthorized" });
    const svc = createClient(url, svcKey);
    const { data: people } = await svc.from("people").select("id").eq("auth_user_id", user.id).limit(1);
    const personId = people?.[0]?.id;
    if (!personId) return json(403, { error: "no person record for this user" });
    const body = await req.json();
    const { submissionId, formKey, workspaceSlug, workflowInstanceId, workflowTaskId, subjectType, subjectId, data } = body || {};
    let workspaceId = null, formTemplateId = null;
    if (!submissionId) {
      if (!formKey || !workspaceSlug) return json(400, { error: "formKey and workspaceSlug are required to create a submission" });
      const { data: ws } = await svc.from("business_workspaces").select("id").eq("slug", workspaceSlug).limit(1);
      workspaceId = ws?.[0]?.id ?? null;
      if (!workspaceId) return json(404, { error: "workspace not found" });
      const { data: tmpls } = await svc.from("form_templates").select("id, version, workspace_id").eq("key", formKey).eq("status", "published").or(`workspace_id.eq.${workspaceId},workspace_id.is.null`).order("workspace_id", { ascending: false, nullsFirst: false }).order("version", { ascending: false }).limit(1);
      formTemplateId = tmpls?.[0]?.id ?? null;
      if (!formTemplateId) return json(404, { error: "published form template not found" });
    }
    const { data: result, error } = await svc.rpc("fs_save_draft", {
      p_submission_id: submissionId ?? null, p_form_template_id: formTemplateId, p_workspace_id: workspaceId,
      p_subject_type: subjectType ?? null, p_subject_id: subjectId ?? null,
      p_workflow_instance_id: workflowInstanceId ?? null, p_workflow_task_id: workflowTaskId ?? null,
      p_data: data ?? {}, p_actor: personId,
    });
    if (error) return json(400, { error: error.message });
    return json(200, { ok: true, submissionId: result });
  } catch (e) { return json(500, { error: String(e) }); }
});

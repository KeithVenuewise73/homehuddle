// Venuewise Core — Edge Function: workflow-advance
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const svcKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json(401, { error: "unauthorized" });

    const svc = createClient(url, svcKey);
    const { data: people } = await svc.from("people").select("id").eq("auth_user_id", user.id).limit(1);
    const personId = people?.[0]?.id;
    if (!personId) return json(403, { error: "no person record for this user" });

    const body = await req.json();
    const { instanceId } = body || {};
    if (!instanceId) return json(400, { error: "instanceId is required" });

    const { data: inst } = await svc.from("workflow_instances")
      .select("workspace_id").eq("id", instanceId).limit(1);
    const workspaceId = inst?.[0]?.workspace_id;
    if (!workspaceId) return json(404, { error: "instance not found" });
    const { data: member } = await svc.from("workspace_members")
      .select("id").eq("workspace_id", workspaceId).eq("person_id", personId).eq("status", "active").limit(1);
    if (!member?.[0]) return json(403, { error: "not a member of this workspace" });

    const { data, error } = await svc.rpc("wf_advance", { p_instance_id: instanceId, p_actor: personId });
    if (error) return json(400, { error: error.message });

    return json(200, { ok: true, instance_status: data });
  } catch (e) {
    return json(500, { error: String(e) });
  }
});

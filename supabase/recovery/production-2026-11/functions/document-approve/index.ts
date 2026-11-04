import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL"); const anon = Deno.env.get("SUPABASE_ANON_KEY"); const svcKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json(401, { error: "unauthorized" });
    const svc = createClient(url, svcKey);
    const { data: people } = await svc.from("people").select("id").eq("auth_user_id", user.id).limit(1);
    const personId = people?.[0]?.id;
    if (!personId) return json(403, { error: "no person record for this user" });
    const body = await req.json();
    const { documentId, decision, comment } = body || {};
    if (!documentId || !decision) return json(400, { error: "documentId and decision are required" });
    const { data, error } = await svc.rpc("doc_decide_approval", { p_document_id: documentId, p_actor: personId, p_decision: decision, p_comment: comment ?? null });
    if (error) return json(403, { error: error.message });
    return json(200, { ok: true, status: data });
  } catch (e) { return json(500, { error: String(e) }); }
});

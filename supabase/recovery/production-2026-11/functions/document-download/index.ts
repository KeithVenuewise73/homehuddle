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
    const body = await req.json();
    const { documentId, version } = body || {};
    if (!documentId) return json(400, { error: "documentId is required" });
    const { data: doc } = await userClient.from("documents").select("id, current_version").eq("id", documentId).maybeSingle();
    if (!doc) return json(403, { error: "not authorized to access this document" });
    const v = version || doc.current_version;
    const svc = createClient(url, svcKey);
    const { data: ver } = await svc.from("document_versions").select("storage_path, version").eq("document_id", documentId).eq("version", v).maybeSingle();
    if (!ver?.storage_path) return json(404, { error: "document version not found" });
    const signed = await svc.storage.from("documents").createSignedUrl(ver.storage_path, 300);
    if (signed.error) return json(500, { error: "sign failed: " + signed.error.message });
    return json(200, { ok: true, url: signed.data.signedUrl, version: v, expiresInSeconds: 300 });
  } catch (e) { return json(500, { error: String(e) }); }
});

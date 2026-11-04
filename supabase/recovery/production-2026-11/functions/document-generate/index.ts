import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
function getPath(obj, path) { return path.split(".").reduce((o, k) => (o == null ? undefined : o[k]), obj); }
function mergeText(text, ctx) { return text.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_m, p) => { const v = getPath(ctx, p.trim()); return v == null ? "" : String(v); }); }
function mergeSpec(spec, ctx) { const walk = (v) => { if (typeof v === "string") return mergeText(v, ctx); if (Array.isArray(v)) return v.map(walk); if (v && typeof v === "object") { const o = {}; for (const k in v) o[k] = walk(v[k]); return o; } return v; }; return walk(spec); }
async function renderPdf(spec) {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const M = 56, W = 612, H = 792, CW = W - 2 * M;
  let page = pdf.addPage([W, H]); let y = H - M;
  const ensure = (need) => { if (y - need < M) { page = pdf.addPage([W, H]); y = H - M; } };
  const wrap = (t, size, f, maxW) => { const words = String(t || "").split(/\s+/); const lines = []; let line = ""; for (const w of words) { const test = line ? line + " " + w : w; if (f.widthOfTextAtSize(test, size) > maxW && line) { lines.push(line); line = w; } else line = test; } if (line) lines.push(line); return lines; };
  for (const b of (spec?.blocks || [])) {
    if (b.type === "heading") { ensure(28); page.drawText(String(b.text || ""), { x: M, y, size: 16, font: bold, color: rgb(0.12, 0.16, 0.22) }); y -= 26; }
    else if (b.type === "paragraph") { for (const ln of wrap(b.text, 11, font, CW)) { ensure(16); page.drawText(ln, { x: M, y, size: 11, font, color: rgb(0.1, 0.12, 0.15) }); y -= 16; } y -= 6; }
    else if (b.type === "field_row") { ensure(18); page.drawText(String(b.label || "") + ":", { x: M, y, size: 11, font: bold, color: rgb(0.3, 0.35, 0.42) }); page.drawText(String(b.value || ""), { x: M + 150, y, size: 11, font, color: rgb(0.1, 0.12, 0.15) }); y -= 18; }
    else if (b.type === "fields") { for (const it of (b.items || [])) { ensure(18); page.drawText(String(it.label || "") + ":", { x: M, y, size: 11, font: bold, color: rgb(0.3, 0.35, 0.42) }); page.drawText(String(it.value || ""), { x: M + 150, y, size: 11, font, color: rgb(0.1, 0.12, 0.15) }); y -= 18; } }
    else if (b.type === "divider") { ensure(12); page.drawLine({ start: { x: M, y: y - 2 }, end: { x: W - M, y: y - 2 }, thickness: 1, color: rgb(0.8, 0.82, 0.85) }); y -= 14; }
    else if (b.type === "spacer") { y -= (b.height || 16); }
    else if (b.type === "signature_line") { ensure(30); page.drawLine({ start: { x: M, y: y - 2 }, end: { x: M + 250, y: y - 2 }, thickness: 1, color: rgb(0.4, 0.42, 0.45) }); page.drawText(String(b.label || "Signature"), { x: M, y: y - 16, size: 9, font, color: rgb(0.4, 0.45, 0.5) }); y -= 34; }
    else if (b.type === "table") { const cols = b.columns || []; const rows = b.rows || []; const cw = CW / Math.max(cols.length, 1); ensure(22); cols.forEach((c, i) => page.drawText(String(c), { x: M + i * cw, y, size: 10, font: bold, color: rgb(0.3, 0.35, 0.42) })); y -= 14; page.drawLine({ start: { x: M, y: y + 2 }, end: { x: W - M, y: y + 2 }, thickness: 0.5, color: rgb(0.8, 0.82, 0.85) }); y -= 4; for (const r of rows) { ensure(16); (r || []).forEach((cell, i) => page.drawText(String(cell == null ? "" : cell), { x: M + i * cw, y, size: 10, font, color: rgb(0.1, 0.12, 0.15) })); y -= 16; } y -= 6; }
  }
  return await pdf.save();
}
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
    const { documentTemplateKey, workspaceSlug, workflowInstanceId, workflowTaskId, formSubmissionId, subjectType, subjectId, documentId, name, requiredRole, custom } = body || {};
    if (!documentTemplateKey || !workspaceSlug) return json(400, { error: "documentTemplateKey and workspaceSlug are required" });
    const { data: ws } = await svc.from("business_workspaces").select("id,slug,name,workspace_type").eq("slug", workspaceSlug).limit(1);
    const wsRow = ws?.[0];
    if (!wsRow) return json(404, { error: "workspace not found" });
    const { data: mem } = await svc.from("workspace_members").select("id").eq("workspace_id", wsRow.id).eq("person_id", personId).eq("status", "active").limit(1);
    if (!mem?.[0]) return json(403, { error: "not a member of the workspace" });
    const { data: tmpls } = await svc.from("document_templates").select("id,version,name,content_spec,subject_type").eq("key", documentTemplateKey).eq("status", "published").or(`workspace_id.eq.${wsRow.id},workspace_id.is.null`).order("workspace_id", { ascending: false, nullsFirst: false }).order("version", { ascending: false }).limit(1);
    const tmpl = tmpls?.[0];
    if (!tmpl) return json(404, { error: "published document template not found" });
    const { data: brand } = await svc.from("workspace_branding").select("*").eq("workspace_id", wsRow.id).maybeSingle();
    let workflow = null, task = null;
    if (workflowInstanceId) { const { data } = await svc.from("workflow_instances").select("*").eq("id", workflowInstanceId).maybeSingle(); workflow = data; }
    if (workflowTaskId) { const { data } = await svc.from("workflow_tasks").select("*").eq("id", workflowTaskId).maybeSingle(); task = data; }
    const formCtx = {}; let formSubs = [];
    if (formSubmissionId) { const { data } = await svc.from("form_submissions").select("id,data,form_template_id").eq("id", formSubmissionId); formSubs = data || []; }
    else if (workflowInstanceId) { const { data } = await svc.from("form_submissions").select("id,data,form_template_id").eq("workflow_instance_id", workflowInstanceId).eq("status", "completed"); formSubs = data || []; }
    for (const fs of formSubs) { const { data: ft } = await svc.from("form_templates").select("key").eq("id", fs.form_template_id).maybeSingle(); if (ft?.key) formCtx[ft.key] = fs.data; }
    const now = new Date();
    const ctx = { workspace: { name: wsRow.name, slug: wsRow.slug, type: wsRow.workspace_type, branding: brand || {} }, workflow: workflow ? { title: workflow.title, status: workflow.status, ...(workflow.context || {}) } : {}, task: task ? { key: task.key, name: task.name, status: task.status } : {}, form: formCtx, now: { date: now.toISOString().slice(0, 10), datetime: now.toISOString().slice(0, 16).replace("T", " "), time: now.toISOString().slice(11, 16), iso: now.toISOString() }, custom: custom || {} };
    const mergedSpec = mergeSpec(tmpl.content_spec || {}, ctx);
    const bytes = await renderPdf(mergedSpec);
    const hashBuf = await crypto.subtle.digest("SHA-256", bytes);
    const contentHash = Array.from(new Uint8Array(hashBuf)).map((b) => b.toString(16).padStart(2, "0")).join("");
    const path = `${wsRow.id}/${workflowInstanceId || subjectId || "adhoc"}/doc-${crypto.randomUUID()}.pdf`;
    const up = await svc.storage.from("documents").upload(path, new Blob([bytes], { type: "application/pdf" }), { contentType: "application/pdf", upsert: true });
    if (up.error) return json(500, { error: "upload failed: " + up.error.message });
    const { data: result, error } = await svc.rpc("doc_create_version", { p_document_id: documentId ?? null, p_workspace_id: wsRow.id, p_document_template_id: tmpl.id, p_template_version: tmpl.version, p_workflow_instance_id: workflowInstanceId ?? null, p_workflow_task_id: workflowTaskId ?? null, p_subject_type: subjectType ?? tmpl.subject_type ?? null, p_subject_id: subjectId ?? null, p_name: name ?? tmpl.name, p_storage_path: path, p_file_size: bytes.length, p_content_hash: contentHash, p_form_submission_id: formSubmissionId ?? (formSubs.length === 1 ? formSubs[0].id : null), p_merge_context: ctx, p_required_role: requiredRole ?? null, p_actor: personId });
    if (error) return json(400, { error: error.message });
    const signed = await svc.storage.from("documents").createSignedUrl(path, 600);
    return json(200, { ok: true, document_id: result?.document_id, version: result?.version, workflow_status: result?.workflow_status, path, url: signed.error ? null : signed.data.signedUrl });
  } catch (e) { return json(500, { error: String(e), stack: (e && e.stack) ? String(e.stack) : undefined }); }
});

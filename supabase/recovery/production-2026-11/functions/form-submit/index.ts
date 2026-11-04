import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
function isEmpty(v) { if (v === null || v === undefined) return true; if (typeof v === "string") return v.trim() === ""; if (Array.isArray(v)) return v.length === 0; return false; }
function evalVisible(cond, ctx) {
  if (!cond || Object.keys(cond).length === 0) return true;
  if (cond.all) return cond.all.every((c) => evalVisible(c, ctx));
  if (cond.any) return cond.any.some((c) => evalVisible(c, ctx));
  if (cond.not) return !evalVisible(cond.not, ctx);
  if (cond.field !== undefined) { const v = ctx[cond.field];
    if (cond.equals !== undefined) return v === cond.equals;
    if (cond.in !== undefined) return Array.isArray(cond.in) && cond.in.includes(v);
    if (cond.notEquals !== undefined) return v !== cond.notEquals;
    if (cond.isSet !== undefined) return cond.isSet ? !isEmpty(v) : isEmpty(v); }
  return true;
}
function validateField(field, value, ctx, path, errors) {
  if (!evalVisible(field.visible_if, ctx)) return;
  if (field.field_type === "info") return;
  if (field.required && isEmpty(value)) { errors.push({ field: path, message: `${field.label} is required` }); return; }
  if (isEmpty(value)) return;
  const r = field.validation || {}; const s = typeof value === "string" ? value : String(value);
  if (r.minLength && s.length < r.minLength) errors.push({ field: path, message: `${field.label} is too short` });
  if (r.maxLength && s.length > r.maxLength) errors.push({ field: path, message: `${field.label} is too long` });
  if (r.min !== undefined && Number(value) < r.min) errors.push({ field: path, message: `${field.label} is below minimum` });
  if (r.max !== undefined && Number(value) > r.max) errors.push({ field: path, message: `${field.label} is above maximum` });
  if (r.pattern && !(new RegExp(r.pattern)).test(s)) errors.push({ field: path, message: `${field.label} is invalid` });
  if ((r.email || field.field_type === "email") && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s)) errors.push({ field: path, message: `${field.label} must be a valid email` });
}
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
    const { submissionId, data } = body || {};
    if (!submissionId) return json(400, { error: "submissionId is required" });
    const { data: subs } = await svc.from("form_submissions").select("id, form_template_id, status").eq("id", submissionId).limit(1);
    const sub = subs?.[0];
    if (!sub) return json(404, { error: "submission not found" });
    if (sub.status !== "draft") return json(409, { error: "submission already submitted" });
    const { data: sections } = await svc.from("form_sections").select("*").eq("form_template_id", sub.form_template_id).order("position", { ascending: true });
    const { data: fields } = await svc.from("form_fields").select("*").eq("form_template_id", sub.form_template_id).order("position", { ascending: true });
    const ctx = {};
    for (const s of sections || []) { if (!s.repeatable) Object.assign(ctx, (data?.[s.key]) || {}); }
    const errors = [];
    for (const s of sections || []) {
      if (!evalVisible(s.visible_if, ctx)) continue;
      const sectionFields = (fields || []).filter((f) => f.section_id === s.id);
      if (s.repeatable) {
        const rows = Array.isArray(data?.[s.key]) ? data[s.key] : [];
        if (rows.length < (s.min_repeat || 0)) errors.push({ field: s.key, message: `${s.name || s.key} needs at least ${s.min_repeat} entries` });
        if (s.max_repeat && rows.length > s.max_repeat) errors.push({ field: s.key, message: `${s.name || s.key} allows at most ${s.max_repeat} entries` });
        rows.forEach((row, i) => { for (const f of sectionFields) validateField(f, row?.[f.key], { ...ctx, ...row }, `${s.key}[${i}].${f.key}`, errors); });
      } else {
        const row = (data?.[s.key]) || {};
        for (const f of sectionFields) validateField(f, row?.[f.key], { ...ctx, ...row }, `${s.key}.${f.key}`, errors);
      }
    }
    if (errors.length) return json(422, { ok: false, errors });
    const { data: result, error } = await svc.rpc("fs_submit", { p_submission_id: submissionId, p_data: data ?? {}, p_actor: personId });
    if (error) return json(400, { error: error.message });
    return json(200, { ok: true, result });
  } catch (e) { return json(500, { error: String(e) }); }
});

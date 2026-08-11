// ============================================================================
// Edge Function: delete-account
// Apple 5.1.1(v) in-app account deletion. Called by the account page with the
// signed-in user's JWT. It invokes the owner-scoped `request_account_deletion`
// RPC *as the user* (so the DB enforces that only the family OWNER can delete),
// flags the billing subscription to cancel at period end, and returns the
// scheduled hard-delete date.
//
// It does NOT blind-DELETE anything. Hard deletion happens after the grace
// window via a separate service-role job; accounting/billing rows are retained.
//
// SECURITY: needs SUPABASE_URL + the request's Authorization (user JWT). The
// service-role key is used ONLY to flag the subscription for cancellation.
//
// ⚠️ SOURCE FOR REVIEW — NOT DEPLOYED.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405, headers: cors });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "not authenticated" }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
  }

  let familyId: string;
  let reason: string | null = null;
  try {
    const b = await req.json();
    familyId = b.family_id;
    reason = b.reason ?? null;
    if (!familyId) throw new Error("family_id required");
  } catch {
    return new Response(JSON.stringify({ error: "family_id required" }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
  }

  // 1. Act AS THE USER so the RPC's owner-check + RLS apply.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: reqRow, error: rpcErr } = await asUser.rpc("request_account_deletion", {
    p_family_id: familyId, p_reason: reason, p_grace_days: 7,
  });

  if (rpcErr) {
    // Non-owner members cannot delete the whole family. Instead, honor Apple's
    // "delete my account" for THIS user by removing only their own membership —
    // shared family data is untouched.
    if (/owner/.test(rpcErr.message)) {
      const { error: memErr } = await asUser.rpc("delete_my_membership");
      if (memErr) {
        return new Response(JSON.stringify({ error: memErr.message }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({
        ok: true, scope: "membership",
        message: "Your access has been removed from this family. The family account itself is managed by its owner.",
      }), { headers: { ...cors, "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify({ error: rpcErr.message }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
  }

  // 2. Flag billing to cancel at period end (service role). Actual provider
  //    cancellation (Stripe subscription / Apple) is reconciled by the billing
  //    webhooks; StoreKit subscriptions must also be cancelled by the user in
  //    iOS Settings (Apple does not allow apps to cancel StoreKit subs) — the
  //    UI explains this.
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  await admin.from("subscriptions")
    .update({ cancel_at_period_end: true, updated_at: new Date().toISOString() })
    .eq("family_id", familyId);

  return new Response(JSON.stringify({
    ok: true,
    scheduled_for: reqRow?.scheduled_for ?? null,
    message: "Your account is scheduled for deletion. You can sign back in within 7 days to cancel.",
  }), { headers: { ...cors, "Content-Type": "application/json" } });
});

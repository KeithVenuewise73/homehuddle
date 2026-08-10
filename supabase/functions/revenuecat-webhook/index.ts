// ============================================================================
// Edge Function: revenuecat-webhook
// The iOS entitlement WRITER. RevenueCat calls this on purchase/renew/expire;
// we reconcile Apple/StoreKit state into the SAME canonical `subscriptions`
// row the web uses (source='apple', product='homehuddle') so one family = one
// entitlement across web + iOS. Founder slots are claimed server-side here.
//
// SECURITY: runs as service_role. The RevenueCat shared-secret and the service
// role key come from environment secrets — NEVER hardcode. Configure in
// Supabase → Edge Functions → Secrets:
//   REVENUECAT_WEBHOOK_AUTH   (matches the Authorization header set in RC)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (provided by the platform)
//
// ⚠️ SOURCE FOR REVIEW — NOT DEPLOYED. `supabase functions deploy` is a
//    separate, CEO-approved step.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RC_AUTH = Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? "";

// StoreKit product ids configured in App Store Connect (placeholders; final ids
// are set once the Apple org clears — see docs/appstore/app-store-connect-checklist.md).
const FOUNDING_PRODUCT_SUFFIX = "founding"; // e.g. net.venuewise.homehuddle.sub.founding

function mapStatus(type: string, expirationMs?: number): string {
  const active = !expirationMs || expirationMs > Date.now();
  switch (type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
    case "PRODUCT_CHANGE":
      return active ? "active" : "canceled";
    case "TRIAL_STARTED":
    case "TRIAL_CONVERTED":
      return "trialing";
    case "CANCELLATION":
      return active ? "active" : "canceled"; // cancellation ≠ immediate loss
    case "BILLING_ISSUE":
      return "past_due";
    case "EXPIRATION":
      return "canceled";
    default:
      return active ? "active" : "canceled";
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  // 1. Authenticate the webhook (constant-value shared secret set in RC).
  const auth = req.headers.get("Authorization") ?? "";
  if (!RC_AUTH || auth !== `Bearer ${RC_AUTH}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body: any;
  try { body = await req.json(); } catch { return new Response("Bad JSON", { status: 400 }); }
  const ev = body?.event;
  if (!ev) return new Response("No event", { status: 400 });

  const familyId: string | undefined = ev.app_user_id;         // we set app_user_id = family_id
  const productId: string = ev.product_id ?? "";
  const type: string = ev.type ?? "";
  const expirationMs: number | undefined = ev.expiration_at_ms ?? undefined;
  if (!familyId) return new Response("No app_user_id", { status: 202 }); // anon/pre-login purchase; ignore

  const supa = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  const status = mapStatus(type, expirationMs);
  const isFounding = productId.endsWith(FOUNDING_PRODUCT_SUFFIX);

  // 2. Upsert the canonical entitlement row (source='apple'). One row per
  //    (family_id, product) thanks to the unique index in migration 0001.
  const { error: upErr } = await supa
    .from("subscriptions")
    .upsert({
      family_id: familyId,
      product: "homehuddle",
      source: "apple",
      status,
      current_period_end: expirationMs ? new Date(expirationMs).toISOString() : null,
      trial_end: type.startsWith("TRIAL") && expirationMs ? new Date(expirationMs).toISOString() : null,
      apple_original_transaction_id: ev.original_transaction_id ?? null,
      revenuecat_app_user_id: familyId,
      updated_at: new Date().toISOString(),
    }, { onConflict: "family_id,product" });

  if (upErr) {
    console.error("subscriptions upsert failed", upErr);
    return new Response("DB error", { status: 500 });
  }

  // 3. Founder claim — server-side, race-safe (only on a real paid founding purchase).
  if (isFounding && (type === "INITIAL_PURCHASE" || type === "TRIAL_CONVERTED" || type === "RENEWAL")) {
    const { data: won, error: fErr } = await supa.rpc("claim_founder_slot", {
      p_family_id: familyId, p_product: "homehuddle", p_source: "apple",
      p_ref: ev.original_transaction_id ?? null,
    });
    if (fErr) console.error("claim_founder_slot failed", fErr);
    else if (won === false) console.warn("founding slot unavailable for", familyId);
  }

  return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
});

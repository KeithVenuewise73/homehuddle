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
  const periodType: string = ev.period_type ?? "";        // TRIAL | INTRO | NORMAL
  const isPaidPeriod = periodType === "NORMAL";           // qualifying = first paid period
  const originalTx = ev.original_transaction_id ?? null;
  const ref = originalTx ?? familyId;

  // 2. Upsert the PURCHASE record for this SOURCE (source='apple'). One row per
  //    (family_id, product, source) — Stripe & Apple coexist (migration 0001).
  const { error: upErr } = await supa
    .from("subscriptions")
    .upsert({
      family_id: familyId,
      product: "homehuddle",
      source: "apple",
      status,
      current_period_end: expirationMs ? new Date(expirationMs).toISOString() : null,
      trial_end: periodType === "TRIAL" && expirationMs ? new Date(expirationMs).toISOString() : null,
      apple_original_transaction_id: originalTx,
      revenuecat_app_user_id: familyId,
      updated_at: new Date().toISOString(),
    }, { onConflict: "family_id,product,source" });

  if (upErr) {
    console.error("subscriptions upsert failed", upErr);   // ids only, no PII
    return new Response("DB error", { status: 500 });
  }

  // 3. Founder slot lifecycle (server is the authority; a client claim is never
  //    trusted — this only runs on an authenticated RevenueCat event).
  if (isFounding) {
    if (type === "INITIAL_PURCHASE" && !isPaidPeriod) {
      // Founding trial started → RESERVE a slot (may fail if sold out).
      const { data: ok } = await supa.rpc("reserve_founder_slot",
        { p_family_id: familyId, p_product: "homehuddle", p_source: "apple", p_ref: ref });
      if (ok === false) console.warn("founding sold out at reserve for", familyId);
    } else if (isPaidPeriod && (type === "INITIAL_PURCHASE" || type === "TRIAL_CONVERTED" || type === "RENEWAL" || type === "UNCANCELLATION")) {
      // First (or continuing) qualifying PAID period → GRANT/finalize the slot.
      const { data: ok } = await supa.rpc("grant_founder_slot",
        { p_family_id: familyId, p_product: "homehuddle", p_source: "apple", p_ref: ref });
      if (ok === false) console.warn("founding grant failed (sold out) for", familyId);
    } else if (type === "EXPIRATION") {
      // Trial/subscription ended without an active paid period → RELEASE the slot.
      await supa.rpc("release_founder_slot", { p_family_id: familyId, p_product: "homehuddle" });
    }
  }

  // 4. Recompute the CANONICAL entitlement from all purchase records.
  const { error: recErr } = await supa.rpc("recompute_entitlement",
    { p_family_id: familyId, p_product: "homehuddle" });
  if (recErr) console.error("recompute_entitlement failed", recErr);

  return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
});

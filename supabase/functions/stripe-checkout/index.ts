// ============================================================================
// Edge Function: stripe-checkout  (WEB Standard/Founder checkout — CANONICAL)
// ----------------------------------------------------------------------------
// Brought under version control from deployed v8 and corrected to the locked
// commercial model (Phase 4):
//   • Founder eligibility comes from the GLOBAL founder pool via
//     founder_slots_remaining('homehuddle') — the SAME 100-cap Apple/RevenueCat
//     consume (no separate Stripe cap, no 150).
//   • Purchase records are product/source-aware: product='homehuddle',
//     source='stripe', upsert onConflict (family_id,product,source) — matches the
//     webhook, so Stripe & Apple rows coexist and a family may have 2 rows.
//   • Reads families.family_name (real column); multi-source-safe (no .single()).
//   • 14-day trial applies to STANDARD ONLY. Founding ($4.99) receives NO
//     introductory trial (canonical model, CEO-confirmed 2026-08).
//
// The Founder SLOT is reserved/granted by stripe-webhook (reserve on
// checkout.session.completed, grant on first paid invoice) — this function only
// decides which PRICE to present while the global pool has capacity. A rare race
// (many checkouts when 1 slot remains) is reconciled by the webhook, which only
// grants while slots remain; excess founding purchases are flagged for ops.
//
// SECRETS from env only. ⚠️ SOURCE FOR REVIEW — deployed prod (v8) UNCHANGED
// until a CEO-approved deploy. Rollback artifact: docs/appstore/stripe-checkout.v8.prod.ts
// ============================================================================
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const STRIPE_SECRET    = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── Price resolution — LOOKUP KEYS ARE AUTHORITATIVE ────────────────────────
// Resolve prices by Stripe **lookup key** (unambiguous words) and fall back to
// a pinned price id only if the lookup fails. This removes the visual-ambiguity
// risk (l/1, O/0) that previously affected the hardcoded ids.
//
// CEO-VERIFIED 2026-08 (canonical Stripe config):
//   founding_member_monthly → price_1T1iAoPqdDGv5YmH0F88NED9  ($4.99/mo)
//   standard_monthly        → price_1T1iApPqdDGv5YmHcxaaDG1J  ($9.99/mo)
// The founding price is Stripe's product "default price"; that designation is
// NOT used for eligibility here (see below) — Founder access is decided solely
// by the shared founder_slots_remaining() pool.
const FOUNDING_LOOKUP_KEY = Deno.env.get('STRIPE_FOUNDING_LOOKUP_KEY') ?? 'founding_member_monthly';
const STANDARD_LOOKUP_KEY = Deno.env.get('STRIPE_STANDARD_LOOKUP_KEY') ?? 'standard_monthly';
const PRICE_FOUNDING_FALLBACK = Deno.env.get('STRIPE_FOUNDING_PRICE_ID') ?? 'price_1T1iAoPqdDGv5YmH0F88NED9'; // $4.99 (CEO-verified)
const PRICE_STANDARD_FALLBACK = Deno.env.get('STRIPE_STANDARD_PRICE_ID') ?? 'price_1T1iApPqdDGv5YmHcxaaDG1J'; // $9.99 (CEO-verified)
const TRIAL_DAYS = 14; // STANDARD only — Founding gets no introductory trial
const SITE_URL = 'https://venuewise.net';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}
async function stripePost(path: string, body: Record<string, unknown>) {
  const params = new URLSearchParams();
  const flatten = (obj: Record<string, unknown>, prefix = '') => {
    for (const [k, v] of Object.entries(obj)) {
      const key = prefix ? `${prefix}[${k}]` : k;
      if (v !== null && typeof v === 'object' && !Array.isArray(v)) flatten(v as Record<string, unknown>, key);
      else if (Array.isArray(v)) v.forEach((item, i) => { if (typeof item === 'object') flatten(item as Record<string, unknown>, `${key}[${i}]`); else params.append(`${key}[${i}]`, String(item)); });
      else params.append(key, String(v));
    }
  };
  flatten(body);
  const res = await fetch(`https://api.stripe.com/v1/${path}`, { method: 'POST', headers: { 'Authorization': `Bearer ${STRIPE_SECRET}`, 'Content-Type': 'application/x-www-form-urlencoded' }, body: params.toString() });
  return res.json();
}

// Resolve a price id from an unambiguous lookup key; fall back to a pinned id.
async function resolvePrice(lookupKey: string, fallbackId: string): Promise<string> {
  try {
    const res = await fetch(`https://api.stripe.com/v1/prices?lookup_keys[]=${encodeURIComponent(lookupKey)}&active=true&limit=1`,
      { headers: { 'Authorization': `Bearer ${STRIPE_SECRET}` } });
    const data = await res.json();
    if (data?.data?.[0]?.id) return data.data[0].id;
  } catch (_e) { /* fall through */ }
  return fallbackId;  // lookup unavailable → pinned id (env override or hardcoded)
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE);
  const token = authHeader.replace('Bearer ', '');
  const { data: { user }, error: authErr } = await sb.auth.getUser(token);
  if (authErr || !user) return json({ error: 'Unauthorized' }, 401);

  const { family_id } = await req.json();
  if (!family_id) return json({ error: 'family_id required' }, 400);

  const { data: person } = await sb.from('people').select('id, phone').eq('auth_user_id', user.id).maybeSingle();
  if (!person) return json({ error: 'Person not found' }, 404);

  // Existing STRIPE purchase record for this family (multi-source safe).
  const { data: existingSub } = await sb.from('subscriptions')
    .select('stripe_customer_id, status')
    .eq('family_id', family_id).eq('product', 'homehuddle').eq('source', 'stripe')
    .maybeSingle();
  if (existingSub && ['active', 'trialing'].includes(existingSub.status)) {
    return json({ error: 'Already subscribed' }, 400);
  }

  // Founder price ONLY while the GLOBAL pool (shared with Apple) has capacity.
  const { data: remaining } = await sb.rpc('founder_slots_remaining', { p_product: 'homehuddle' });
  const foundingAvailable = (typeof remaining === 'number' ? remaining : 0) > 0;
  const isFounding = foundingAvailable;
  // Resolve by lookup key (authoritative, ambiguity-proof); fall back to pinned id.
  const priceId = isFounding
    ? await resolvePrice(FOUNDING_LOOKUP_KEY, PRICE_FOUNDING_FALLBACK)
    : await resolvePrice(STANDARD_LOOKUP_KEY, PRICE_STANDARD_FALLBACK);

  let customerId = existingSub?.stripe_customer_id;
  if (!customerId) {
    const { data: family } = await sb.from('families').select('family_name, email').eq('id', family_id).maybeSingle();
    const customer = await stripePost('customers', {
      email: family?.email || '', name: family?.family_name || '',
      metadata: { family_id, person_id: person.id },
    });
    customerId = customer.id;
  }

  // Trial: STANDARD gets the 14-day free trial; FOUNDING gets none.
  const subData: Record<string, unknown> = {
    'subscription_data[metadata][family_id]': family_id,
    'subscription_data[metadata][founding]': isFounding ? 'true' : 'false',
  };
  if (!isFounding) subData['subscription_data[trial_period_days]'] = TRIAL_DAYS;

  const session = await stripePost('checkout/sessions', {
    customer: customerId, mode: 'subscription',
    'line_items[0][price]': priceId, 'line_items[0][quantity]': 1,
    ...subData,
    success_url: `${SITE_URL}/homehuddle/calendar.html?checkout=success`,
    cancel_url: `${SITE_URL}/homehuddle/join.html?checkout=cancelled`,
    'payment_method_types[0]': 'card',
  });
  if (!session.url) return json({ error: 'Failed to create checkout session', detail: session }, 500);

  // Product/source-aware purchase record (coexists with Apple; matches webhook).
  await sb.from('subscriptions').upsert({
    family_id, product: 'homehuddle', source: 'stripe',
    stripe_customer_id: customerId, stripe_price_id: priceId,
    status: 'incomplete', founder: isFounding, updated_at: new Date().toISOString(),
  }, { onConflict: 'family_id,product,source' });

  return json({ url: session.url, price_tier: isFounding ? 'founding' : 'standard', trial_days: isFounding ? 0 : TRIAL_DAYS });
});

// ============================================================================
// RETAINED ROLLBACK ARTIFACT — production stripe-checkout VERSION 8 (verbatim).
// Currently-deployed. Captured before the canonical-model correction in
// supabase/functions/stripe-checkout/. Redeploy THIS to restore prior behavior.
// Do not edit.
//
// KNOWN ISSUES (why it is being replaced — see the corrected version):
//   • EARLY_ADOPTER_LIMIT = 150 (canonical is 100)
//   • Founder eligibility = count of active/trialing Stripe subs — NOT the global
//     founder_grants pool; does NOT share the cap with Apple/RevenueCat
//   • .single() on subscriptions breaks once a family has 2 sources (stripe+apple)
//   • reads families.name (column is family_name) → empty Stripe customer name
//   • upsert onConflict 'stripe_customer_id' (webhook uses family_id,product,source)
// ============================================================================
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const STRIPE_SECRET    = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const PRICE_EARLY     = 'price_1TliAoPqdDGv5YmHOF88NED9'; // $4.99 early adopter (live)
const PRICE_STANDARD  = 'price_1TliApPqdDGv5YmHcxaaDG1J'; // $9.99 standard (live)
const EARLY_ADOPTER_LIMIT = 150;
const TRIAL_DAYS = 14;
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
  const { data: person } = await sb.from('people').select('id, phone').eq('auth_user_id', user.id).single();
  if (!person) return json({ error: 'Person not found' }, 404);
  const { data: existingSub } = await sb.from('subscriptions').select('stripe_customer_id, status').eq('family_id', family_id).single();
  if (existingSub && ['active', 'trialing'].includes(existingSub.status)) return json({ error: 'Already subscribed' }, 400);
  const { count } = await sb.from('subscriptions').select('*', { count: 'exact', head: true }).in('status', ['active', 'trialing']);
  const priceId = (count ?? 0) < EARLY_ADOPTER_LIMIT ? PRICE_EARLY : PRICE_STANDARD;
  const isEarlyAdopter = priceId === PRICE_EARLY;
  let customerId = existingSub?.stripe_customer_id;
  if (!customerId) {
    const { data: family } = await sb.from('families').select('name, email').eq('id', family_id).single();
    const customer = await stripePost('customers', { email: family?.email || '', name: family?.name || '', metadata: { family_id, person_id: person.id } });
    customerId = customer.id;
  }
  const session = await stripePost('checkout/sessions', {
    customer: customerId, mode: 'subscription',
    'line_items[0][price]': priceId, 'line_items[0][quantity]': 1,
    'subscription_data[trial_period_days]': TRIAL_DAYS,
    'subscription_data[metadata][family_id]': family_id,
    'subscription_data[metadata][early_adopter]': isEarlyAdopter ? 'true' : 'false',
    success_url: `${SITE_URL}/homehuddle/calendar.html?checkout=success`,
    cancel_url: `${SITE_URL}/homehuddle/join.html?checkout=cancelled`,
    'payment_method_types[0]': 'card',
  });
  if (!session.url) return json({ error: 'Failed to create checkout session', detail: session }, 500);
  await sb.from('subscriptions').upsert({ family_id, stripe_customer_id: customerId, stripe_price_id: priceId, status: 'incomplete', updated_at: new Date().toISOString() }, { onConflict: 'stripe_customer_id' });
  return json({ url: session.url, price_tier: isEarlyAdopter ? 'early_adopter' : 'standard', trial_days: TRIAL_DAYS });
});

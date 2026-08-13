// ============================================================================
// Edge Function: stripe-webhook  (WEB billing → canonical entitlement)
// ----------------------------------------------------------------------------
// Brought under version control from the deployed function (v6) and integrated
// into the SAME canonical architecture as RevenueCat (Sprint 02, Phase 2):
//   • writes purchase records with product='homehuddle', source='stripe'
//     (onConflict family_id,product,source → coexists with Apple rows)
//   • Founder uses the SAME reserve→grant→release rules as Apple
//   • EVERY relevant event calls recompute_entitlement()
//
// Business rules are shared with Apple — no separate Stripe founder logic.
// SECRETS from env only. ⚠️ SOURCE FOR REVIEW — the deployed prod version is
// UNCHANGED until a CEO-approved deploy. Diff vs prod is documented in the PR.
// ============================================================================
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const STRIPE_SECRET         = Deno.env.get('STRIPE_SECRET_KEY')!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;
const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE      = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// Founding Stripe price (CEO-verified 2026-08). Overridable via env for staging.
// Used only as a SECONDARY founder signal; the PRIMARY signal is the
// subscription metadata `founding` flag that stripe-checkout stamps from the
// shared founder pool — so a price-id change can never silently break detection.
const FOUNDING_PRICE_ID     = Deno.env.get('STRIPE_FOUNDING_PRICE_ID') ?? 'price_1T1iAoPqdDGv5YmH0F88NED9';

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

async function verifyStripeSignature(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  const parts = sigHeader.split(',');
  const ts  = parts.find(p => p.startsWith('t='))?.split('=')[1];
  const sig = parts.find(p => p.startsWith('v1='))?.split('=')[1];
  if (!ts || !sig) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name:'HMAC', hash:'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${ts}.${payload}`));
  const expected = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2,'0')).join('');
  return timingSafeEqual(expected, sig);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const payload   = await req.text();
  const sigHeader = req.headers.get('stripe-signature') || '';
  if (!(await verifyStripeSignature(payload, sigHeader, STRIPE_WEBHOOK_SECRET))) {
    return new Response('Invalid signature', { status: 400 });   // never trust an unsigned event
  }

  const event = JSON.parse(payload);
  const sb  = createClient(SUPABASE_URL, SUPABASE_SERVICE, { auth: { persistSession: false } });
  const obj = event.data?.object;

  // Resolve family_id for customer-keyed events (invoices/charges).
  async function familyByCustomer(customerId: string): Promise<string | null> {
    if (!customerId) return null;
    const { data } = await sb.from('subscriptions')
      .select('family_id').eq('stripe_customer_id', customerId).eq('source', 'stripe')
      .eq('product', 'homehuddle').maybeSingle();
    return data?.family_id ?? null;
  }
  const recompute = (fid: string | null) =>
    fid ? sb.rpc('recompute_entitlement', { p_family_id: fid, p_product: 'homehuddle' }) : Promise.resolve();

  let familyId: string | null = null;

  switch (event.type) {
    case 'checkout.session.completed': {
      familyId = obj.metadata?.family_id ?? null;
      const subscriptionId = obj.subscription;
      if (!familyId || !subscriptionId) break;

      const subRes = await fetch(`https://api.stripe.com/v1/subscriptions/${subscriptionId}`,
        { headers: { 'Authorization': `Bearer ${STRIPE_SECRET}` } });
      const sub = await subRes.json();
      const priceId = sub.items?.data?.[0]?.price?.id;
      // PRIMARY: the pool-derived flag checkout stamped on the subscription.
      // SECONDARY: price-id equality (kept as a defensive fallback).
      const isFounding = sub.metadata?.founding === 'true' || priceId === FOUNDING_PRICE_ID;

      await sb.from('subscriptions').upsert({
        family_id: familyId, product: 'homehuddle', source: 'stripe',
        stripe_customer_id: obj.customer, stripe_subscription_id: subscriptionId, stripe_price_id: priceId,
        status: sub.status,
        trial_end:          sub.trial_end          ? new Date(sub.trial_end * 1000).toISOString()          : null,
        current_period_end: sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null,
        cancel_at_period_end: sub.cancel_at_period_end ?? false,
        founder: isFounding, updated_at: new Date().toISOString(),
      }, { onConflict: 'family_id,product,source' });

      // Founding trial start → RESERVE (paid-now checkout → GRANT below on invoice paid).
      if (isFounding) {
        await sb.rpc('reserve_founder_slot',
          { p_family_id: familyId, p_product: 'homehuddle', p_source: 'stripe', p_ref: subscriptionId });
      }
      break;
    }

    case 'customer.subscription.updated':
    case 'customer.subscription.deleted': {
      familyId = obj.metadata?.family_id ?? null;
      if (!familyId) break;
      const priceId = obj.items?.data?.[0]?.price?.id;
      await sb.from('subscriptions').update({
        stripe_subscription_id: obj.id, stripe_price_id: priceId,
        status: event.type === 'customer.subscription.deleted' ? 'canceled' : obj.status,
        trial_end:          obj.trial_end          ? new Date(obj.trial_end * 1000).toISOString()          : null,
        current_period_end: obj.current_period_end ? new Date(obj.current_period_end * 1000).toISOString() : null,
        cancel_at_period_end: obj.cancel_at_period_end ?? false,
        updated_at: new Date().toISOString(),
      }).eq('family_id', familyId).eq('product', 'homehuddle').eq('source', 'stripe');

      // Trial that ended without ever converting → release the RESERVATION only.
      // (release_founder_slot refuses to touch a GRANTED slot — never re-pooled.)
      if (event.type === 'customer.subscription.deleted') {
        await sb.rpc('release_founder_slot', { p_family_id: familyId, p_product: 'homehuddle' });
      }
      break;
    }

    case 'invoice.payment_failed': {
      familyId = await familyByCustomer(obj.customer);
      await sb.from('subscriptions').update({ status: 'past_due', updated_at: new Date().toISOString() })
        .eq('stripe_customer_id', obj.customer).eq('source', 'stripe');
      break;
    }

    case 'invoice.payment_succeeded': {
      familyId = await familyByCustomer(obj.customer);
      await sb.from('subscriptions').update({ status: 'active', updated_at: new Date().toISOString() })
        .eq('stripe_customer_id', obj.customer).eq('source', 'stripe');
      // First qualifying PAID period for a Founding sub → GRANT (idempotent, permanent).
      // Prefer the subscription metadata flag (pool-derived) over price-id equality.
      const line = obj.lines?.data?.[0];
      const isFounding = obj.subscription_details?.metadata?.founding === 'true'
        || line?.metadata?.founding === 'true'
        || line?.price?.id === FOUNDING_PRICE_ID;
      const isPaid = (obj.amount_paid ?? 0) > 0;
      if (familyId && isFounding && isPaid) {
        await sb.rpc('grant_founder_slot',
          { p_family_id: familyId, p_product: 'homehuddle', p_source: 'stripe', p_ref: obj.subscription ?? null });
      }
      break;
    }

    case 'charge.refunded': {
      familyId = await familyByCustomer(obj.customer);
      break;   // recompute below reflects any resulting state; Founder grant is permanent
    }
  }

  await recompute(familyId);
  return new Response(JSON.stringify({ received: true }), { headers: { 'Content-Type': 'application/json' } });
});

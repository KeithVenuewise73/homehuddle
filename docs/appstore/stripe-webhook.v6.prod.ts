// ============================================================================
// RETAINED ROLLBACK ARTIFACT — production stripe-webhook VERSION 6 (verbatim).
// This is the CURRENTLY-DEPLOYED production function, captured before the
// integrated replacement in supabase/functions/stripe-webhook/. If the new
// version misbehaves in production, redeploy THIS to restore prior behavior.
// Do not edit. (Uses the old single-row onConflict:'family_id' model.)
// ============================================================================
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const STRIPE_SECRET         = Deno.env.get('STRIPE_SECRET_KEY')!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;
const SUPABASE_URL          = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE      = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

async function verifyStripeSignature(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  const parts = sigHeader.split(',');
  const ts  = parts.find(p => p.startsWith('t='))?.split('=')[1];
  const sig = parts.find(p => p.startsWith('v1='))?.split('=')[1];
  if (!ts || !sig) return false;
  const signed = `${ts}.${payload}`;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name:'HMAC', hash:'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signed));
  const expected = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2,'0')).join('');
  return expected === sig;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const payload   = await req.text();
  const sigHeader = req.headers.get('stripe-signature') || '';
  const valid = await verifyStripeSignature(payload, sigHeader, STRIPE_WEBHOOK_SECRET);
  if (!valid) return new Response('Invalid signature', { status: 400 });

  const event = JSON.parse(payload);
  const sb  = createClient(SUPABASE_URL, SUPABASE_SERVICE);
  const obj = event.data?.object;

  switch (event.type) {
    case 'checkout.session.completed': {
      const familyId = obj.metadata?.family_id;
      const subscriptionId = obj.subscription;
      if (!familyId || !subscriptionId) break;

      const subRes = await fetch(`https://api.stripe.com/v1/subscriptions/${subscriptionId}`, {
        headers: { 'Authorization': `Bearer ${STRIPE_SECRET}` }
      });
      const sub = await subRes.json();

      await sb.from('subscriptions').upsert({
        family_id:              familyId,
        stripe_customer_id:     obj.customer,
        stripe_subscription_id: subscriptionId,
        stripe_price_id:        sub.items?.data?.[0]?.price?.id,
        status:                 sub.status,
        trial_end:              sub.trial_end        ? new Date(sub.trial_end * 1000).toISOString()        : null,
        current_period_end:     sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null,
        cancel_at_period_end:   sub.cancel_at_period_end ?? false,
        updated_at:             new Date().toISOString(),
      }, { onConflict: 'family_id' });
      break;
    }

    case 'customer.subscription.updated':
    case 'customer.subscription.deleted': {
      const familyId = obj.metadata?.family_id;
      if (!familyId) break;
      await sb.from('subscriptions').update({
        stripe_subscription_id: obj.id,
        stripe_price_id:        obj.items?.data?.[0]?.price?.id,
        status:                 event.type === 'customer.subscription.deleted' ? 'canceled' : obj.status,
        trial_end:              obj.trial_end        ? new Date(obj.trial_end * 1000).toISOString()        : null,
        current_period_end:     obj.current_period_end ? new Date(obj.current_period_end * 1000).toISOString() : null,
        cancel_at_period_end:   obj.cancel_at_period_end ?? false,
        updated_at:             new Date().toISOString(),
      }).eq('family_id', familyId);
      break;
    }

    case 'invoice.payment_failed': {
      const customerId = obj.customer;
      if (!customerId) break;
      await sb.from('subscriptions').update({ status: 'past_due', updated_at: new Date().toISOString() })
        .eq('stripe_customer_id', customerId);
      break;
    }

    case 'invoice.payment_succeeded': {
      const customerId = obj.customer;
      if (!customerId) break;
      await sb.from('subscriptions').update({ status: 'active', updated_at: new Date().toISOString() })
        .eq('stripe_customer_id', customerId).eq('status', 'past_due');
      break;
    }
  }

  return new Response(JSON.stringify({ received: true }), { headers: { 'Content-Type': 'application/json' } });
});

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const STRIPE_SECRET   = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL    = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RETURN_URL = 'https://venuewise.net/homehuddle/account.html';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' } });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE);
  const { data: { user }, error: authErr } = await sb.auth.getUser(authHeader.replace('Bearer ', ''));
  if (authErr || !user) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });

  const { family_id } = await req.json();
  if (!family_id) return new Response(JSON.stringify({ error: 'family_id required' }), { status: 400 });

  // Get stripe_customer_id for this family
  const { data: sub } = await sb.from('subscriptions')
    .select('stripe_customer_id')
    .eq('family_id', family_id)
    .single();

  if (!sub?.stripe_customer_id) {
    return new Response(JSON.stringify({ error: 'No subscription found' }), { status: 404 });
  }

  // Create Stripe billing portal session
  const params = new URLSearchParams({
    customer: sub.stripe_customer_id,
    return_url: RETURN_URL,
  });

  const res = await fetch('https://api.stripe.com/v1/billing_portal/sessions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${STRIPE_SECRET}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params.toString(),
  });

  const session = await res.json();
  if (!session.url) {
    return new Response(JSON.stringify({ error: 'Failed to create portal session', detail: session }), { status: 500 });
  }

  return new Response(JSON.stringify({ url: session.url }), {
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
});

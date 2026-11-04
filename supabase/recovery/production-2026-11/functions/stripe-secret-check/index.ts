import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
Deno.serve(async () => {
  const key = Deno.env.get('STRIPE_SECRET_KEY');
  if (!key) return new Response(JSON.stringify({ok:false,msg:'STRIPE_SECRET_KEY not found'}),{headers:{'Content-Type':'application/json'}});
  const valid = key.startsWith('sk_test_') || key.startsWith('sk_live_');
  return new Response(JSON.stringify({ok:valid, prefix:key.slice(0,12)+'...'}),{headers:{'Content-Type':'application/json'}});
});

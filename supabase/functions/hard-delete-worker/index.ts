// ============================================================================
// Edge Function: hard-delete-worker  (DAILY scheduled job)
// ----------------------------------------------------------------------------
// Sprint 02, Phase 4. Completes account deletions whose 7-day grace has expired.
// Runs as service_role. Per family, in order, IDEMPOTENT and RETRY-SAFE:
//   1. verify still due (due_for_deletion)
//   2. cancel Stripe subscription(s)          (external)
//   3. delete RevenueCat customer identity     (external)
//   4. delete Supabase Auth users for members  (external)
//   5. only if ALL external steps succeeded → hard_delete_family() (PG purge)
//   6. on ANY external failure → leave the account due, log retryable, next run
//   7. log completion WITHOUT PII
//
// Invocation: schedule daily (e.g. Supabase Scheduled Functions / an external
// cron hitting this URL with the service key). NOT pg_cron — external providers
// need coordination + retries. ⚠️ SOURCE FOR REVIEW — NOT DEPLOYED.
//
// Secrets (env only): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
//   STRIPE_SECRET_KEY, REVENUECAT_SECRET_API_KEY (v2 REST, starts sk_...),
//   REVENUECAT_PROJECT_ID.  Any missing external secret => that step is a
//   retryable failure (the account is NOT purged until it can be done cleanly).
// ============================================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL   = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const STRIPE_SECRET  = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const RC_SECRET      = Deno.env.get('REVENUECAT_SECRET_API_KEY') ?? '';
const RC_PROJECT     = Deno.env.get('REVENUECAT_PROJECT_ID') ?? '';

const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

async function cancelStripe(familyId: string): Promise<boolean> {
  try {
    const { data } = await sb.from('subscriptions')
      .select('stripe_subscription_id').eq('family_id', familyId).eq('source', 'stripe');
    for (const row of data ?? []) {
      if (!row.stripe_subscription_id) continue;
      if (!STRIPE_SECRET) return false;                  // cannot do it cleanly → retry later
      // DELETE is idempotent: a already-canceled sub returns 200/404, both fine.
      const res = await fetch(`https://api.stripe.com/v1/subscriptions/${row.stripe_subscription_id}`,
        { method: 'DELETE', headers: { Authorization: `Bearer ${STRIPE_SECRET}` } });
      if (!res.ok && res.status !== 404) return false;
    }
    return true;
  } catch { return false; }
}

async function deleteRevenueCat(familyId: string): Promise<boolean> {
  // RevenueCat App User ID == family_id (we logIn with it). Deleting the customer
  // is idempotent (404 = already gone). If not configured, treat as retryable.
  try {
    if (!RC_SECRET || !RC_PROJECT) return false;
    const res = await fetch(
      `https://api.revenuecat.com/v2/projects/${RC_PROJECT}/customers/${encodeURIComponent(familyId)}`,
      { method: 'DELETE', headers: { Authorization: `Bearer ${RC_SECRET}` } });
    return res.ok || res.status === 404;
  } catch { return false; }
}

async function deleteAuthUsers(familyId: string): Promise<boolean> {
  try {
    const { data } = await sb.from('family_members').select('person_id').eq('family_id', familyId);
    for (const m of data ?? []) {
      if (!m.person_id) continue;
      const { error } = await sb.auth.admin.deleteUser(m.person_id);
      // "user not found" is fine (idempotent); any other error is retryable.
      if (error && !/not.?found/i.test(error.message)) return false;
    }
    return true;
  } catch { return false; }
}

Deno.serve(async (_req) => {
  const { data: due, error } = await sb.rpc('due_for_deletion');
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const summary = { due: (due ?? []).length, purged: 0, retried: 0 };
  for (const row of due ?? []) {
    const fid = row.family_id;
    const okStripe = await cancelStripe(fid);
    const okRC     = await deleteRevenueCat(fid);
    const okAuth   = await deleteAuthUsers(fid);

    if (okStripe && okRC && okAuth) {
      const { data: purged } = await sb.rpc('hard_delete_family', { p_family_id: fid });
      if (purged) summary.purged++;
    } else {
      summary.retried++;
      // Record retryable state WITHOUT PII (family_id is not personal data).
      await sb.from('client_errors').insert({
        kind: 'deletion_retry', platform: 'server', path: 'hard-delete-worker',
        message: `deferred family=${fid} stripe=${okStripe} rc=${okRC} auth=${okAuth}`,
      });
    }
  }
  console.log('hard-delete-worker', summary);   // ids/counts only, no PII
  return new Response(JSON.stringify({ ok: true, ...summary }), { headers: { 'Content-Type': 'application/json' } });
});

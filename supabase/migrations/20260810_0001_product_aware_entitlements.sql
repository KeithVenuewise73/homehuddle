-- ============================================================================
-- 0001 · Product-aware entitlement model  (ADDITIVE / NON-DESTRUCTIVE)
-- ----------------------------------------------------------------------------
-- Goal (Sprint 01, Phase 2): let ONE canonical entitlement represent
--   (family_id, product, source, status) so WEB/Stripe, iOS/Apple, and later
--   Google/AthleteHuddle/HighlightAI all resolve to the SAME family — no
--   duplicate identities, no billing rebuild.
--
-- Approach: extend the EXISTING `subscriptions` table (reuse, don't replace)
-- with product/source/founder columns + provider refs, backfill current rows,
-- and expose a SECURITY INVOKER view that reads through existing RLS.
--
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION. Return for CEO approval.
--    Existing Stripe data is preserved; every add is guarded with IF NOT EXISTS.
-- ============================================================================

begin;

-- 1. New dimensions (safe defaults keep every existing row valid) ------------
alter table public.subscriptions
  add column if not exists product text not null default 'homehuddle',
  add column if not exists source  text not null default 'stripe',
  add column if not exists founder boolean not null default false,
  add column if not exists apple_original_transaction_id text,
  add column if not exists revenuecat_app_user_id text,
  add column if not exists google_purchase_token text;

-- 2. Constrain the vocabulary (future products/sources are pre-allowed) -------
alter table public.subscriptions
  drop constraint if exists subscriptions_product_check,
  add  constraint subscriptions_product_check
       check (product in ('homehuddle','athletehuddle','highlightai'));

alter table public.subscriptions
  drop constraint if exists subscriptions_source_check,
  add  constraint subscriptions_source_check
       check (source in ('stripe','apple','google'));

-- 3. One canonical row per (family, product). The `source` column records which
--    provider currently owns the billing. Reconciliation (see docs) updates the
--    same row rather than inserting a duplicate → prevents double-entitlement.
create unique index if not exists subscriptions_family_product_uidx
  on public.subscriptions (family_id, product);

-- 4. Backfill existing rows to the canonical model ---------------------------
--    (columns already defaulted; only founder needs deriving from the live
--     Early-Adopter price id.)
update public.subscriptions
   set founder = true
 where source = 'stripe'
   and stripe_price_id = 'price_1TliAoPqdDGv5YmHOF88NED9'  -- live $4.99 Early Adopter
   and founder = false;

-- 5. Canonical entitlement view (SECURITY INVOKER → honors subscriptions RLS,
--    so a user only ever sees their own family's entitlements). ---------------
create or replace view public.v_family_entitlements
with (security_invoker = true) as
select
  s.family_id,
  s.product,
  s.source,
  s.status,
  s.founder,
  (s.status in ('trialing','active','past_due')) as is_active,
  s.trial_end,
  s.current_period_end,
  s.cancel_at_period_end,
  s.updated_at
from public.subscriptions s;

comment on view public.v_family_entitlements is
  'Canonical per-family product entitlement. is_active = trialing|active|past_due. Product-aware for homehuddle/athletehuddle/highlightai across stripe/apple/google.';

commit;

-- ROLLBACK (reference):
--   drop view if exists public.v_family_entitlements;
--   drop index if exists public.subscriptions_family_product_uidx;
--   alter table public.subscriptions
--     drop constraint if exists subscriptions_product_check,
--     drop constraint if exists subscriptions_source_check,
--     drop column if exists product, drop column if exists source,
--     drop column if exists founder,
--     drop column if exists apple_original_transaction_id,
--     drop column if exists revenuecat_app_user_id,
--     drop column if exists google_purchase_token;

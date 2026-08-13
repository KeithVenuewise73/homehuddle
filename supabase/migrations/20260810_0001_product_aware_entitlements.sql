-- ============================================================================
-- 0001 · Product-aware entitlements — PURCHASE RECORDS vs CANONICAL ENTITLEMENT
-- ----------------------------------------------------------------------------
-- CEO-validation fix (V2): the first draft used ONE subscriptions row per
-- (family_id, product), so a Stripe row and an Apple row for the same family
-- would OVERWRITE each other and lose purchase history.
--
-- Corrected model separates the two concerns:
--   • public.subscriptions            = PURCHASE / SOURCE records (billing truth).
--       One row per (family_id, product, SOURCE) → Stripe + Apple coexist.
--   • public.family_product_entitlements = CANONICAL "does family X have product Y?"
--       One row per (family_id, product), recomputed from all purchase records.
--
-- This reliably answers entitlement while preserving per-source history.
-- ADDITIVE / NON-DESTRUCTIVE. Existing Stripe rows are preserved & backfilled.
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

-- 1. Purchase/source dimensions on the existing table ------------------------
alter table public.subscriptions
  add column if not exists product text not null default 'homehuddle',
  add column if not exists source  text not null default 'stripe',
  add column if not exists founder boolean not null default false,
  add column if not exists apple_original_transaction_id text,
  add column if not exists revenuecat_app_user_id text,
  add column if not exists google_purchase_token text;

alter table public.subscriptions
  drop constraint if exists subscriptions_product_check,
  add  constraint subscriptions_product_check
       check (product in ('homehuddle','athletehuddle','highlightai'));
alter table public.subscriptions
  drop constraint if exists subscriptions_source_check,
  add  constraint subscriptions_source_check
       check (source in ('stripe','apple','google'));

-- One purchase record per (family, product, SOURCE) — sources COEXIST.
create unique index if not exists subscriptions_family_product_source_uidx
  on public.subscriptions (family_id, product, source);

update public.subscriptions
   set founder = true
 where source = 'stripe'
   -- $4.99 Founding price: accept BOTH id spellings. The CEO-stated canonical id
   -- (1/0) and the id observed on the live founding subscription (l/O) differ only
   -- in ambiguous glyphs; matching both ensures the existing founding subscriber is
   -- backfilled regardless of which spelling live Stripe actually uses.
   and stripe_price_id in ('price_1T1iAoPqdDGv5YmH0F88NED9', 'price_1TliAoPqdDGv5YmHOF88NED9')
   and founder = false;

-- 2. Canonical entitlement table --------------------------------------------
create table if not exists public.family_product_entitlements (
  family_id          uuid not null references public.families(id) on delete cascade,
  product            text not null,
  is_active          boolean not null default false,
  active_source      text,                 -- which source currently grants it
  founder            boolean not null default false,
  current_period_end timestamptz,
  trial_end          timestamptz,
  updated_at         timestamptz not null default now(),
  primary key (family_id, product),
  constraint fpe_product_check check (product in ('homehuddle','athletehuddle','highlightai'))
);

alter table public.family_product_entitlements enable row level security;

drop policy if exists fpe_select_own on public.family_product_entitlements;
create policy fpe_select_own on public.family_product_entitlements
  for select to authenticated
  using (family_id in (select current_family_ids(false)));

drop policy if exists fpe_admin_select on public.family_product_entitlements;
create policy fpe_admin_select on public.family_product_entitlements
  for select to authenticated using (public.is_admin());

drop policy if exists fpe_service_all on public.family_product_entitlements;
create policy fpe_service_all on public.family_product_entitlements
  for all to service_role using (true) with check (true);

-- 3. Recompute canonical entitlement from ALL purchase records for a family --
--    Called by BOTH billing webhooks (Stripe + RevenueCat) after any change.
--    is_active if ANY source is trialing/active/past_due, OR canceled but the
--    paid period has not yet elapsed (grace at period end).
create or replace function public.recompute_entitlement(p_family_id uuid, p_product text default 'homehuddle')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active   boolean;
  v_source   text;
  v_period   timestamptz;
  v_trial    timestamptz;
  v_founder  boolean;
begin
  select
    bool_or(s.status in ('trialing','active','past_due')
            or (s.status = 'canceled' and s.current_period_end > now())),
    max(s.current_period_end),
    max(s.trial_end),
    bool_or(s.founder)
  into v_active, v_period, v_trial, v_founder
  from public.subscriptions s
  where s.family_id = p_family_id and s.product = p_product;

  -- Prefer the source of an actually-active purchase for active_source.
  select s.source into v_source
  from public.subscriptions s
  where s.family_id = p_family_id and s.product = p_product
    and (s.status in ('trialing','active','past_due')
         or (s.status = 'canceled' and s.current_period_end > now()))
  order by s.current_period_end desc nulls last
  limit 1;

  insert into public.family_product_entitlements
    (family_id, product, is_active, active_source, founder, current_period_end, trial_end, updated_at)
  values
    (p_family_id, p_product, coalesce(v_active,false), v_source, coalesce(v_founder,false), v_period, v_trial, now())
  on conflict (family_id, product) do update
    set is_active = excluded.is_active,
        active_source = excluded.active_source,
        founder = excluded.founder,
        current_period_end = excluded.current_period_end,
        trial_end = excluded.trial_end,
        updated_at = now();
end;
$$;

revoke all on function public.recompute_entitlement(uuid, text) from public, anon, authenticated;
grant execute on function public.recompute_entitlement(uuid, text) to service_role;

-- 4. Backfill canonical rows from existing purchase records -------------------
insert into public.family_product_entitlements (family_id, product, is_active, active_source, founder, current_period_end, trial_end)
select s.family_id, s.product,
       bool_or(s.status in ('trialing','active','past_due') or (s.status='canceled' and s.current_period_end > now())),
       (array_agg(s.source order by s.current_period_end desc nulls last))[1],
       bool_or(s.founder),
       max(s.current_period_end), max(s.trial_end)
from public.subscriptions s
group by s.family_id, s.product
on conflict (family_id, product) do nothing;

commit;

-- ROLLBACK (reference):
--   drop function if exists public.recompute_entitlement(uuid, text);
--   drop table if exists public.family_product_entitlements;
--   drop index if exists public.subscriptions_family_product_source_uidx;
--   alter table public.subscriptions
--     drop constraint if exists subscriptions_product_check,
--     drop constraint if exists subscriptions_source_check,
--     drop column if exists product, drop column if exists source, drop column if exists founder,
--     drop column if exists apple_original_transaction_id,
--     drop column if exists revenuecat_app_user_id, drop column if exists google_purchase_token;

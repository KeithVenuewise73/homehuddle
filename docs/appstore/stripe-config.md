# Stripe configuration & manual actions (HomeHuddle)

CEO-verified canonical config (2026-08). Code resolves prices by **lookup key**;
the price ids below are the confirmed live values used only as fallbacks. No live
Stripe change is made by code — this documents what the CEO must set/verify.

## Product & prices (CEO-VERIFIED)
- **Product:** "Venuewise Family Plan" (customer-facing on Stripe Checkout, receipts, invoices, billing portal). Rename to "HomeHuddle Premium" recommended — see manual actions.
- **Founding Member:** $4.99/mo, lookup key **`founding_member_monthly`**, Price ID **`price_1T1iAoPqdDGv5YmH0F88NED9`**. Stripe product **default price = Yes**. First 100 globally. **No introductory trial.**
- **Standard:** $9.99/mo, lookup key **`standard_monthly`**, Price ID **`price_1T1iApPqdDGv5YmHcxaaDG1J`**. **14-day free trial** (applied in code).

Code resolves by lookup key so the exact glyphs no longer gate a charge.

## ⚠️ Founding price-id conflict — UNRESOLVED (needs CEO Stripe confirmation)
Production evidence (HH-IOS-09) contradicts the CEO-stated founding price id:
- **CEO-stated canonical:** `price_1T1iAoPqdDGv5YmH0F88NED9` (glyphs `1` / `0`).
- **Observed live:** the single live founding subscription (status `trialing`, $4.99)
  references **`price_1TliAoPqdDGv5YmHOF88NED9`** (glyphs `l` / `O`). Only this id is
  *proven* to exist in live Stripe.

These differ only in the ambiguous `l/1` and `O/0` glyphs and denote the same $4.99
product. Until the CEO confirms the exact id by **copy-paste from the Stripe dashboard**,
the code does not bet on either:
- checkout resolves by **lookup key** `founding_member_monthly` (primary);
- webhook founder detection uses the subscription **metadata `founding` flag** (primary)
  and, as fallback, treats **both** id spellings as founding (`KNOWN_FOUNDING_PRICE_IDS`);
- migration 0001 backfills founding on **either** id spelling.

**CEO action:** open the $4.99 price in Stripe → copy the exact Price ID and the exact
lookup key → paste them here so we can pin one id and delete the other.

## ⚠️ Deploy-order dependency — schema BEFORE functions (HARD)
The corrected `stripe-checkout` / `stripe-webhook` require schema that production
does NOT yet have (verified HH-IOS-09): `subscriptions.{product,source,founder}`,
the `unique(family_id,product,source)` index, the `family_product_entitlements` /
`founder_grants` / `founder_config` tables, and the founder / `recompute_entitlement`
RPCs. **Migrations 0001 + 0002 (minimum) must be applied first.** Deploying the
functions onto the current schema would break billing (writes to non-existent
columns, calls to non-existent RPCs). Applying migrations is a separate,
CEO-authorized DB step — not covered by the HH-IOS-09 function-deploy authorization.

## Founder eligibility is NOT the Stripe default price
Stripe marks the Founding $4.99 price as the product **default price**. This has
**zero effect** on our eligibility logic:
- `stripe-checkout` always passes an explicit `line_items[0][price]`, so the default price is never auto-selected.
- Founder eligibility is decided **only** by `founder_slots_remaining('homehuddle')` (the shared 100 pool across Stripe + Apple). A non-eligible user resolves the **Standard** price regardless of which price Stripe marks default.
- The webhook confirms Founder via the subscription **metadata `founding` flag** (pool-derived), with price-id equality as a defensive fallback.

Result: a user who is not Founder-eligible can never receive $4.99 because Stripe
marks it default. Verified in application logic.

## Trial policy (canonical)
- **Standard:** 14-day trial applied in code — `subscription_data[trial_period_days]=14` (only when `!isFounding`). Not on the price, so no double-trial.
- **Founding:** **no trial.** Checkout omits `trial_period_days` for the founding price; the web/app Founding card says "no trial, locked rate"; the Apple `.founding` product must have **no introductory offer** in App Store Connect.

## Env to set at deploy (Supabase → Edge Functions → Secrets)
Lookup keys are the default; price-id overrides optional:
```
STRIPE_STANDARD_LOOKUP_KEY = standard_monthly          # (default)
STRIPE_FOUNDING_LOOKUP_KEY = founding_member_monthly   # (default)
# Optional pinned-id fallbacks (CEO-verified live ids — used only if lookup fails):
STRIPE_STANDARD_PRICE_ID = price_1T1iApPqdDGv5YmHcxaaDG1J
STRIPE_FOUNDING_PRICE_ID = price_1T1iAoPqdDGv5YmH0F88NED9
```
Already present: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_*`.

## Manual Stripe Dashboard actions
| Action | Priority | Why |
|---|---|---|
| Confirm lookup key `founding_member_monthly` is on the $4.99 price and `standard_monthly` on the $9.99 price | **REQUIRED BEFORE LAUNCH** | Checkout resolves by these keys |
| Ensure the Founding price/label shows **no "first 150" / "early adopter" / trial** text | **REQUIRED BEFORE LAUNCH** | Label is customer-facing on Checkout/receipts; must match the 100-cap, no-trial model |
| Rename Product "Venuewise Family Plan" → "HomeHuddle Premium" (+ description) | RECOMMENDED | Brand consistency on Checkout/receipts/portal |
| Leave both prices with **no price-level trial** | DO NOT CHANGE | Code applies the Standard 14-day trial; a price-level trial would double it |
| Leave Default Price as-is (Founding) | DO NOT CHANGE | Irrelevant to checkout (explicit price passed); does not affect eligibility |

**Backend cap is authoritative at 100** via `founder_slots_remaining('homehuddle')`
(shared Stripe + Apple pool). No `150` and no `early_adopter_monthly` remain in
active HomeHuddle billing code (only the retained `stripe-checkout.v8.prod.ts`
rollback artifact preserves the pre-correction values verbatim).

# Stripe configuration & manual actions (HomeHuddle)

CEO-verified canonical config (2026-08). Code resolves prices by **lookup key**;
the price ids below are the confirmed live values used only as fallbacks. No live
Stripe change is made by code — this documents what the CEO must set/verify.

## Product & prices (CEO-VERIFIED)
- **Product:** "Venuewise Family Plan" (customer-facing on Stripe Checkout, receipts, invoices, billing portal). Rename to "HomeHuddle Premium" recommended — see manual actions.
- **Founding Member:** $4.99/mo, lookup key **`founding_member_monthly`**, Price ID **`price_1T1iAoPqdDGv5YmH0F88NED9`**. Stripe product **default price = Yes**. First 100 globally. **No introductory trial.**
- **Standard:** $9.99/mo, lookup key **`standard_monthly`**, Price ID **`price_1T1iApPqdDGv5YmHcxaaDG1J`**. **14-day free trial** (applied in code).

The earlier `l/1` + `O/0` price-id transcription discrepancy is **resolved**: the
dashboard values above are canonical, and code additionally resolves by lookup key
so the exact glyphs no longer gate a charge.

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

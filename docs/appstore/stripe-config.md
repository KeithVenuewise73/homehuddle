# Stripe configuration & manual actions (HomeHuddle)

Verified from the Stripe dashboard (CEO) + the deployed `stripe-checkout` source.
No live Stripe change is made by code — this documents what the CEO must set/verify.

## Product & prices (verified)
- **Product:** "Venuewise Family Plan" (customer-facing on Stripe Checkout page, receipts, invoices, and the billing portal).
- **Founder:** $4.99/mo, lookup key **`early_adopter_monthly`**, dashboard label "Early Adopter — first 150" (stale), 0 active subs, no price-level trial, Default Price = Yes.
- **Standard:** $9.99/mo, lookup key **`standard_monthly`**, label "Standard", 0 active subs, no price-level trial, Default Price = No.

## ⚠️ Price-ID transcription discrepancy (MUST resolve before charging)
The dashboard-transcribed ids differ from the machine-sourced (deployed-function) ids
in exactly the ambiguous characters `l`↔`1` and `O`↔`0`:

| Tier | Deployed/code (machine-exact) | Dashboard (hand-typed) | Δ |
|---|---|---|---|
| Founder | `price_1TliAoPqdDGv5YmHOF88NED9` | `price_1T1iAoPqdDGv5YmH0F88NED9` | pos8 l/1, pos22 O/0 |
| Standard | `price_1TliApPqdDGv5YmHcxaaDG1J` | `price_1T1iApPqdDGv5YmHcxaaDG1J` | pos8 l/1 |

Neither can be assumed correct. **Resolution (chosen): resolve by lookup key.**
`stripe-checkout` now fetches the price by its lookup key (`standard_monthly` /
`early_adopter_monthly`) — unambiguous words — and only falls back to a pinned id
if the lookup fails.

## Env to set at deploy (Supabase → Edge Functions → Secrets)
Lookup keys are the default; overrides optional:
```
STRIPE_STANDARD_LOOKUP_KEY = standard_monthly       # (default)
STRIPE_FOUNDING_LOOKUP_KEY = early_adopter_monthly  # (default)
# Optional pinned-id fallbacks — set ONLY by copy-paste from the dashboard:
STRIPE_STANDARD_PRICE_ID = <paste exact>
STRIPE_FOUNDING_PRICE_ID = <paste exact>
```
Already present: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_*`.

## Trial
- Standard 14-day trial is applied **in code** (`subscription_data[trial_period_days]=14`), not on the price — correct given the prices have no direct trial.
- **Founder currently ALSO receives the 14-day trial** (checkout applies the trial to whichever price is selected). The canonical model lists a trial only under Standard. **CEO DECISION:** should Founder get a 14-day trial? If NO, apply the trial only when `!isFounding` in `stripe-checkout` and remove "14 days free" from the Founding paywall card + the StoreKit founding intro offer. Left unchanged pending your decision (existing web copy currently promises "Free for 14 days").

## Default Price assessment → IRRELEVANT (for checkout)
`stripe-checkout` always passes an explicit `line_items[0][price]`, so Stripe's
Product "Default Price" is never used by checkout. Default Price only matters for
integrations that create subscriptions without specifying a price (we don't).

## Manual Stripe Dashboard actions
| Action | Priority | Why |
|---|---|---|
| Rename Founder label "Early Adopter — first 150" → "Founding Member" (and it does not surface a cap) | **REQUIRED BEFORE LAUNCH** | The "150" label is customer-facing on Checkout/receipts and contradicts the 100-cap model |
| Confirm lookup keys `standard_monthly` / `early_adopter_monthly` are attached to the correct $9.99 / $4.99 prices | **REQUIRED BEFORE LAUNCH** | Checkout resolves by these keys |
| Rename Product "Venuewise Family Plan" → "HomeHuddle Premium" (+ update description) | RECOMMENDED | Shown on Checkout page/receipts/portal; align with the app |
| Leave price-level trial blank | DO NOT CHANGE | Code applies the 14-day trial; a price-level trial would double it |
| Change Default Price | DO NOT CHANGE | Irrelevant to checkout (explicit price passed) |
| Decide Founder trial (see Trial above) | **DECISION** | Determines Founder intro offer on Stripe + StoreKit |

**Backend cap is authoritative at 100** via `founder_slots_remaining('homehuddle')`
(shared Stripe+Apple pool). No `150` remains in active HomeHuddle billing code
(only the retained `stripe-checkout.v8.prod.ts` rollback artifact + the stale Stripe label).

# Production Change Inventory (Phase 11) — NOT YET AUTHORIZED

Precise inventory of what a production rollout of this branch would change. **No
execution** — for CEO authorization only.

## A. Database migrations (apply in order)
| # | File | Effect | Destructive? |
|---|------|--------|--------------|
| 0001 | `product_aware_entitlements` | adds `subscriptions` cols (product/source/founder/provider refs) + `unique(family_id,product,source)`; new `family_product_entitlements` table + `recompute_entitlement()`; backfills from existing rows | No — additive; existing Stripe rows preserved |
| 0002 | `founder_slots` | `founder_config`/`founder_grants` + reserve/grant/release + `founder_slots_remaining` | No |
| 0003 | `observability_and_device_tokens` | `client_errors`, `device_tokens` | No |
| 0004 | `account_deletion` | families deletion cols; `account_deletion_requests`; `request/cancel_account_deletion` | No |
| 0005 | `admin_read_access` | admin `is_admin()` SELECT policies (alongside existing) + `admin_dashboard_metrics()` | No |
| 0006 | `account_deletion_completion` | `delete_my_membership`, `hard_delete_family`, `due_for_deletion`, `hard_delete_due_accounts` | No |

All verified on real Postgres: apply in order, **idempotent/re-runnable**, RLS enforced (real-role matrix green). Pre-flight: `select count(*) from subscriptions` to confirm no pre-existing duplicate `(family_id,product,source)` before the unique index (prod currently has 1 sub row).

## B. Edge Functions
| Function | Action | Rollback |
|---|---|---|
| `revenuecat-webhook` | **new** deploy | delete function |
| `delete-account` | **new** deploy | delete function |
| `hard-delete-worker` | **new** deploy + daily schedule | unschedule + delete |
| `stripe-webhook` | **REPLACE** deployed v6 with integrated version | redeploy retained v6 (source: `docs/appstore/stripe-webhook.v6.prod.ts`) |
| `stripe-checkout` | **REPLACE** deployed v8 with canonical version | redeploy retained v8 (source: `docs/appstore/stripe-checkout.v8.prod.ts`) |

**TWO** existing production functions change: `stripe-webhook` (v6→integrated) and
`stripe-checkout` (v8→canonical). The v8 checkout uses a stale Founder mechanism
(150 cap, Stripe-only active/trialing count) that does NOT share the global
Founder-100 pool; the corrected `supabase/functions/stripe-checkout/` decides the
Founder price from `founder_slots_remaining('homehuddle')` (shared with Apple),
is product/source-aware, and is multi-source safe. Both functions resolve prices
by **lookup key** (`founding_member_monthly` / `standard_monthly`) and detect
Founder via the pool + subscription metadata (not the Stripe default price).
Deploy both **last**, together, and watch one live checkout + one webhook event.
Rollback = redeploy the retained v6/v8 artifacts. **New env (optional):**
`STRIPE_STANDARD_PRICE_ID` (CEO-verified `price_1T1iApPqdDGv5YmHcxaaDG1J`),
`STRIPE_FOUNDING_PRICE_ID` (CEO-verified `price_1T1iAoPqdDGv5YmH0F88NED9`).

## C. Web (HTML/JS) — promote via existing `main → live` Pages flow
- `homehuddle/account.html` — in-app deletion, canonical entitlement read, platform-aware Manage Subscription
- `homehuddle/join.html` — iOS→RevenueCat billing routing
- `homehuddle/calendar.html` — canonical entitlement gate, iOS paywall routing, SW skipped on native
- `admin/homehuddle.html` — real `is_admin()` auth + verified metrics
- `index.html`, `homehuddle/index.html`, `join.html`, `terms.html`, `homehuddle-privacy.html`, `homehuddle/admin.html` — pricing/copy normalization
- `account.html` — legacy deletion routed to modern flow
- `support.html` — **new** support page
- `shared/native.js`, `shared/observability.js`, `shared/native-config.example.js` — new modules
- `sw.js` — unchanged (still used by web PWA)

## D. Secrets (set in Supabase Edge Function secrets; never in repo)
- `REVENUECAT_WEBHOOK_AUTH`
- `STRIPE_FOUNDING_PRICE_ID` (optional; defaults to live founding price)
- `REVENUECAT_SECRET_API_KEY`, `REVENUECAT_PROJECT_ID` (hard-delete worker)
- Existing already set: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_*`
- Build-time (native): `shared/native-config.js` with the RevenueCat **public** SDK key

## E. Schedule
- `hard-delete-worker`: daily (e.g. 03:00 UTC) via Supabase Scheduled Functions or an external cron hitting the function URL with the service key. Not pg_cron.

## F. Not changed
Production DB data; DNS; other Edge Functions; the web service worker; AthleteHuddle/HighlightAI.

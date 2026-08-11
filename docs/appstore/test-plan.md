# HomeHuddle iOS launch test plan

Status legend per case:
**CODE VERIFIED** (logic reviewed in repo) · **LOCAL VERIFIED** (ran here) ·
**SANDBOX VERIFIED** (needs Apple sandbox) · **BLOCKED BY APPLE** (needs org).

## Auth
| Case | Status |
|---|---|
| Web: phone OTP signup + verify | CODE VERIFIED (unchanged existing flow) |
| Web: login / logout | CODE VERIFIED |
| iOS: OTP deep-link return (`homehuddle://`) routes into app | CODE VERIFIED · SANDBOX VERIFIED pending build |
| Reviewer seeded account + fixed code | BLOCKED BY APPLE (seed before submit) |

## Family / Calendar
| Case | Status |
|---|---|
| Create family (onboarding RPC) | CODE VERIFIED (unchanged) |
| Invite / member visibility | CODE VERIFIED (unchanged) |
| Calendar renders; feeds sync | CODE VERIFIED (unchanged) |
| Family isolation (RLS: own family only) | LOCAL VERIFIED (pg_policies inspected — authenticated own-family scope) |

## Billing
| Case | Status |
|---|---|
| Web Stripe subscriber logs in → entitlement recognized | CODE VERIFIED (reads `subscriptions`, source-agnostic) |
| iOS: no Stripe checkout reachable | CODE VERIFIED (join routes to RevenueCat on `isNative()`) |
| iOS: purchase Standard / Founding | BLOCKED BY APPLE (needs sandbox + products) |
| iOS: restore purchases | CODE VERIFIED (`VW.native.restorePurchases`) · SANDBOX pending |
| Founder cap = first 100, race-safe | CODE VERIFIED (reserve→grant→release, advisory-locked; slot consumed only on first paid period; released if trial never converts) |
| No double-charge (web sub + app) | CODE VERIFIED (purchase records coexist per source; canonical entitlement checked before offering purchase) |
| Trial 14-day both tiers | CODE VERIFIED (copy + product config) |

## Account
| Case | Status |
|---|---|
| In-app delete (owner only) | CODE VERIFIED (owner check in RPC) |
| Non-owner blocked from deleting shared data | CODE VERIFIED (RPC raises) |
| Grace-window cancel | CODE VERIFIED (`cancel_account_deletion`) |
| Privacy/Terms links present & correct | LOCAL VERIFIED |

## Push
| Case | Status |
|---|---|
| Permission prompt / denial fallback | CODE VERIFIED |
| Token registration → `device_tokens` (no dup) | CODE VERIFIED |
| Notification tap routing | CODE VERIFIED · SANDBOX pending |
| APNs delivery | BLOCKED BY APPLE (APNs key) |
| Web push still works | CODE VERIFIED (unchanged `sw.js`) |

## Admin
| Case | Status |
|---|---|
| Requires authenticated `is_admin()` (PIN removed) | CODE VERIFIED |
| Anon cannot read families/subscriptions | LOCAL VERIFIED (RLS) |
| Founder/Standard/status/source metrics | CODE VERIFIED (needs migration 0005 applied to show data) |

## Automated (ran locally)
- `node scripts/check-pricing.mjs` — pricing/secret guard: **LOCAL VERIFIED**.
- `tests/` Playwright smoke — unchanged; run against a preview URL, not prod, for new copy.

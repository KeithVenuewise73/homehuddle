<!-- Recovered/written 2026-11-04 on branch recovery/venuewise-production-2026-11. Status: PROPOSED — takes effect when this PR is approved and merged. -->

# Edge-function policy — Venuewise / HomeHuddle

Deployed functions today: send-sms-outbox, sms-inbound, smart-task, hyper-action, sync-schedules, workflow-tick, stripe-checkout, stripe-webhook, stripe-secret-check, and 13 more — see supabase/recovery/production-2026-11/functions/. The deployed source is archived under `supabase/recovery/production-2026-11/functions/` with `DEPLOYED.json` per function.

## 1. Every function is authenticated or explicitly public — never accidentally public

Each function's `DEPLOYED.json` records `verify_jwt`. A function with `verify_jwt: false` must, in its first lines, do one of:

- verify a shared secret header with a constant-time compare and **fail closed** when the secret is not configured (reference: `security/stage0/functions/_shared/guards.ts` → `requireSharedSecret`), or
- verify the upstream provider's signature (Twilio `X-Twilio-Signature`, Stripe `Stripe-Signature`) — reference `verifyTwilioSignature` in the same file, or
- carry a comment `// PUBLIC BY DESIGN: <reason>` and touch nothing but read-only, anon-safe data.

Findings this policy closes once applied: SEC-9 (`sms-inbound` accepted unsigned webhooks), SEC-10 (`send-sms-outbox` optional secret), NEW-A/B/C (`smart-task` PIN reset, `hyper-action`, `sync-schedules` open) — Venuewise; NEW-E/F (`hlvs`, `discovery-run`) — HL-BOS.

## 2. Secrets

- Read from `Deno.env` only. Never a literal key, JWT or token in source — `hlvs` and `discovery-run` currently contain literals and are on the Level B list for redeploy.
- The service-role key is used only in functions that must bypass RLS, and those functions must gate every caller (rule 1) before the first service-role query.
- Secret **names** are listed in `DEPLOYED.json` → `env_var_names`; values are never written to the repository, a report or a log.

## 3. Source lives in the repository

`supabase/functions/<slug>/index.ts` on the owning repository is the source. A function that exists only in the platform (true for most of the 43 today) is a defect; the recovered copy under `supabase/recovery/…/functions/` is promoted into `supabase/functions/` by the owner **unchanged** in its first PR, then changed in a second PR, so the diff is reviewable.

## 4. Deploying

- Via CI with a human gate only (HL-BOS: `.github/workflows/deploy.yml`, inert until armed). Never from a laptop or an AI session.
- The deploy PR shows the diff between the archived deployed copy and the new source, the `verify_jwt` setting, and the list of secret names the function expects.
- Rollback = redeploy the previous archived copy (kept under `supabase/recovery/`).

## 5. Tests

Pure logic (signature verification, secret comparison, parsing) lives in `_shared/*.ts` with Deno tests; `security/stage0/functions/_shared/guards.test.ts` (7 tests) is the template and passes locally. Functions that call providers are tested with the provider mocked, never against the live account.

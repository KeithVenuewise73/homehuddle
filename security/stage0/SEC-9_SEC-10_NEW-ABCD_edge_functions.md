# Level B package — Venuewise edge functions: SEC-9, SEC-10, NEW-A, NEW-B, NEW-C, NEW-D

Project: `urwnbskrtoplgnkkxuvl` · Prepared 2026-11-04 · **Status: AWAITING APPROVAL — nothing deployed**

All deployed sources are archived verbatim under `supabase/recovery/production-2026-11/functions/<slug>/`. Proposed replacements are under `security/stage0/functions/<slug>/` and share `security/stage0/functions/_shared/guards.ts` (7 Deno tests, passing locally: `deno test _shared/guards.test.ts` → `ok | 7 passed | 0 failed`). The proposed files parse (`deno lint`), but **full type-checking against `jsr:@supabase/supabase-js` could not run in this environment (no network to the registry)**; it must be run in CI or locally before deploy.

| ID | Function | Deployed | `verify_jwt` | Defect | Proposed |
| --- | --- | --- | --- | --- | --- |
| SEC-9 | `sms-inbound` | v4 | false | No `X-Twilio-Signature` check: anyone can POST a fake STOP/START/consent reply and change `people.sms_opt_in` / parent consent | v5: HMAC-SHA1 signature check against `TWILIO_AUTH_TOKEN` + `SMS_INBOUND_PUBLIC_URL`; 403 on failure; logic otherwise identical |
| SEC-10 | `send-sms-outbox` | v6 | false | `OUTBOX_SECRET` is only enforced if the env var is set. Cron job 10 **does** send an `x-outbox-secret` header (VERIFIED in `cron.job`), so the secret may be configured — but secret values are not readable from here and the function cannot be probed from this environment, so enforcement is **NOT VERIFIED** either way. Plus the outage behaviour (719 failing calls/day) | v7: secret mandatory (fail-closed — removes the ambiguity), circuit breaker, 48h stale-row expiry, per-phone daily cap |
| NEW-A | `smart-task` (PIN reset) | v21 | false | Unauthenticated POST `{email}` **overwrites `feeds.pin` with a random 6-digit code** for any account and emails it. Anyone who knows an email can lock the family out of the legacy PIN login at will; no rate limit | **Decision needed, see below** |
| NEW-B | `hyper-action` (web push) | v21 | false | Unauthenticated POST `{email,title,body}` sends a push notification with arbitrary text to any subscribed user | v22: `x-internal-secret` (`INTERNAL_FN_SECRET`) required, fail-closed |
| NEW-C | `sync-schedules` | v56 | false | Unauthenticated GET/POST runs the full feed sync with the service key (cost + ability to trigger change alerts) | v57: `x-internal-secret` required; cron job 6 passes the header |
| NEW-D | `stripe-secret-check` | v5 | false | Diagnostic that reports whether `STRIPE_SECRET_KEY` is set (not the value). Low risk, no purpose in production | **Delete** (Level B: "deleting diagnostic functions") |

`workflow-tick` already has the right shape (`WF_TICK_SECRET`, `x-cron-secret`) but only enforces when the secret is set — same optional pattern as SEC-10. Set `WF_TICK_SECRET` as part of this package (no code change needed to start enforcing; a v2 with `requireSharedSecret` is recommended later).

## NEW-A decision for the CEO

`smart-task` serves the **legacy** PIN login at `venuewise.net/account/homehuddle.html` (table `feeds`). Phase 2 found the current app uses Supabase Auth (7 auth users) and that the `families` PIN read path can no longer work under current RLS. Two options:

1. **Retire** — set `smart-task` inactive and remove the PIN-reset form from the legacy page. Correct if no family still logs in with a PIN. Validation: `feeds` rows with `is_active = true` and a recent login, which the engineer will report before you decide.
2. **Keep, with limits** — v22 that (a) stores the code in a new `feeds.reset_code` + `reset_expires_at` instead of overwriting `pin`, (b) rate-limits to 3 requests per email per hour via a small `reset_requests` table, (c) requires a Turnstile/hCaptcha token from the page. This is a day of work and a migration; not prepared yet.

Recommendation: option 1 unless the login report shows active PIN users.

## Exact change (per function)

1. Set secrets (names only; values from the CEO's password manager, generated fresh, ≥32 chars): `OUTBOX_SECRET`, `INTERNAL_FN_SECRET`, `WF_TICK_SECRET`, `SMS_INBOUND_PUBLIC_URL` (= `https://urwnbskrtoplgnkkxuvl.supabase.co/functions/v1/sms-inbound`, the exact URL configured in Twilio's messaging webhook).
2. Update cron jobs 10 (`send-sms-outbox-every-2min`), 6 (`sync-schedules-every-30min`) and the workflow tick to send the matching header (`cron.alter_job` on the `command`; current commands are captured in the backup step).
3. Deploy `send-sms-outbox` v7, `sync-schedules` v57, `hyper-action` v22, `sms-inbound` v5 from `security/stage0/functions/` with `verify_jwt=false` (unchanged — the guards replace JWT verification for these machine callers).
4. Delete `stripe-secret-check`.
5. `smart-task`: per the decision above.

## Affected apps
- HomeHuddle web: calls `hyper-action`? **Unknown** — the client source is not in any repository. If the browser calls it directly, v22 will break push notifications until the call is moved behind an authenticated path. Validation step 3 below catches this before cut-over by inspecting `function_edge_logs` callers for 7 days (today: only `send-sms-outbox` and `sync-schedules` show traffic).
- Twilio inbound webhook: v5 only accepts requests Twilio signed. If `SMS_INBOUND_PUBLIC_URL` differs from the URL Twilio uses (trailing slash, query string), every inbound is rejected with 403 — the validation step covers it. Currently moot: the Twilio account is inactive.

## Backup
- Deployed sources: already archived with SHA-256 (`supabase/recovery/production-2026-11/functions/`).
- Cron commands: `select jobid, jobname, command from cron.job` captured in the PR before changing.

## Validation
1. `curl -X POST <fn-url>` without the header → 401 (`sync-schedules`, `hyper-action`, `send-sms-outbox`); with the header → 200 and the same JSON shape as before.
2. `sms-inbound`: replay a request with a signature computed from the test auth token → 200; tamper one byte → 403. (The signature algorithm is covered by `guards.test.ts` against Twilio's published example.)
3. For 7 days after deploy, `function_edge_logs` shows no 401s from unexpected callers.
4. Cron jobs 6, 10 succeed on their next run (`cron.job_run_details.status = 'succeeded'`).

## Rollback
Redeploy the archived v4/v6/v21/v56 bundles from `supabase/recovery/production-2026-11/functions/`; restore the cron commands from the backup. Secrets can stay set (they are ignored by the old versions).

## Risk
Low for NEW-B/NEW-C/SEC-10 (machine callers only, verified by logs). Medium for SEC-9 only because the public URL must match exactly. NEW-A depends on the decision.

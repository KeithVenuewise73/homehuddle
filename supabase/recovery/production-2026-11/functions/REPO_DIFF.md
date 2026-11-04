# Venuewise edge functions — deployed source vs the `homehuddle` repository

22 functions deployed on `urwnbskrtoplgnkkxuvl`, recovered 2026-11-04 via the platform's function API; per-file SHA-256 in `SHA256SUMS.original` (as deployed) and `SHA256SUMS` (as committed). One file is redacted in the committed copy — `verify-phone/index.ts` has a Twilio Account SID in a comment — see `REDACTIONS.md`; the other 22 files are byte-identical to the deployed source.

## Repository coverage

| Function | Deployed | In repo? | Match |
| --- | --- | --- | --- |
| stripe-checkout | v9, 2026-08-13 | `feat/homehuddle-ios-release` | Same code; differs only in comments/blank lines (deployed copy comment-stripped) |
| stripe-webhook | v7, 2026-08-13 | `feat/homehuddle-ios-release` | Same code; comments/blank lines only |
| sync-schedules v56, super-processor v23, hyper-action v21, smart-task v21, smart-function v20, send-notifications v21, verify-phone v6, send-sms-outbox v6, stripe-secret-check v5, stripe-portal v4, sms-inbound v4, workflow-start/task-action/advance/tick v1, form-save/submit v1, document-generate v2, document-download v1, document-approve v1 | — | **not in any branch** | The archive here is the only source (20 of 22 functions) |

`feat/homehuddle-ios-release` also carries `revenuecat-webhook`, `delete-account`, `hard-delete-worker` — **not deployed** (consistent with its migrations 0003–0006 never being applied).

## Deployment dates tell the history
- 2026-05-23: the legacy PIN/feeds generation (`smart-*`, `hyper-action`, `super-processor`)
- 2026-05-30 → 06-24: SMS pipeline, Stripe
- 2026-07-04: workflow, forms, document engines (wave2/wave3) — all v1, never updated
- 2026-08-13: Stripe v9/v7 from the iOS branch
- 2026-08-17 / 08-23: last changes (`sync-schedules` v56, `sms-inbound` v4)

Nothing has been deployed to this project since 2026-08-23.

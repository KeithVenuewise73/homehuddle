# Level B package — SMS pipeline containment and restoration (Twilio)

Project: `urwnbskrtoplgnkkxuvl` · Prepared 2026-11-04 · **Status: AWAITING APPROVAL — nothing changed**

Level C reminder: this package does **not** send SMS, reactivate Twilio, or requeue failed notifications. Those are the CEO's calls and are listed under "Restoration" as decisions, not actions.

## Current state (VERIFIED 2026-11-04, read-only)

| Fact | Value |
| --- | --- |
| `sms_outbox` | 1,040 rows: 381 `sent` (2026-06-25 → 08-23), 659 `failed`, 0 `pending` |
| Failure reasons | "Authenticate" (156 rows, 08-23 → 09-17) then "authentication failed, account … status 4 is not active" (503 rows, 09-18 → 11-03) — the Twilio account is inactive/suspended |
| Cron job 10 `send-sms-outbox-every-2min` | active, `*/2 * * * *`, POSTs to `send-sms-outbox` with Authorization + `x-outbox-secret` headers; ~719 invocations/day, every one returns "nothing pending" since the queue drained |
| Cron job 13 `flush-schedule-digests` | active, every 2 min; `schedule_change_queue` holds 33 unflushed rows (2026-10-01 → 11-03) that would become SMS the moment the provider works |
| Cron job 9 `nightly-reminders-generate` | active, 21:30 and 22:30 daily; `reminders` has 121 rows, 93 undismissed |
| Cron job 11 `escalate-stale-leads-daily` | active; all 20 leads are flagged spam |
| Functions that call Twilio | `send-sms-outbox` (REST Messages), `super-processor` (= send-invite, REST Messages, `verify_jwt` true), `verify-phone` (Twilio Verify, `verify_jwt` true) |
| People opted in | 8 (`people.sms_opt_in = true`); 4 confirmed + 3 pending `family_members`; the only family in production is the owner's own |

Nothing is being delivered and nothing has been delivered since 2026-08-23. The cost today is noise (720 function invocations/day) and a **latent risk**: if the Twilio account is reactivated without first draining the queues, up to 33 stale schedule-change texts plus the nightly reminder backlog go out to the 8 opted-in numbers at once, some of them six weeks old.

## Containment (recommended now, reversible)

### Exact change
```sql
-- C1. Stop the 2-minute sender loop until the provider is restored.
select cron.alter_job(job_id := 10, active := false);   -- send-sms-outbox-every-2min
-- C2. Stop digests from being flushed into sms_outbox.
select cron.alter_job(job_id := 13, active := false);   -- flush-schedule-digests
-- C3. Stop generating new nightly reminders (they cannot be delivered).
select cron.alter_job(job_id := 9,  active := false);   -- nightly-reminders-generate
-- Leave 6 (sync-schedules), 7 (refresh-calendar-events), 8 (refresh-platform-status),
-- 11 (escalate-stale-leads), 12 (capture-sync-reports) running: none of them send.
```

No rows are deleted. `schedule_change_queue` (33) and `reminders` (93) are left in place for the restoration decision.

### Reason
Turns a silent, continuously failing pipeline into an explicitly paused one, and removes the "reactivation sends six weeks of backlog" risk.

### Affected apps
HomeHuddle: schedule-change digests and nightly reminders stop being *generated*; they were not being delivered anyway. Calendar sync and the app itself are unaffected.

### Backup
`select jobid, jobname, schedule, active, command from cron.job` (captured in the PR, secrets redacted in any report).

### Validation
`select jobid, active from cron.job where jobid in (9,10,13)` → all `false`; `cron.job_run_details` shows no new runs for those jobids after the change; `function_edge_logs` for `send-sms-outbox` drops to zero.

### Rollback
`select cron.alter_job(job_id := N, active := true)` for each.

### Risk
Very low.

## Restoration (decisions for the CEO — not prepared as actions)

1. **Provider.** Reactivate the Twilio account (billing/compliance issue on the Twilio side — "status 4 is not active") **or** move to another provider. Either is a purchase/contract decision (Level C). Until decided, containment stays.
2. **Backlog.** Before re-enabling job 10: expire everything older than 48h. Proposed SQL (Level B, separate approval):
   ```sql
   update public.schedule_change_queue set flushed_at = now(), flush_note = 'expired_2026-11_recovery'
    where flushed_at is null and created_at < now() - interval '48 hours';
   -- exact column names to be confirmed against the live table before approval
   ```
   and let `send-sms-outbox` v7's stale guard handle anything that slips through.
3. **Consent.** Re-verify the 8 opted-in numbers' consent is still valid after a 10-week silence (TCPA: a long gap plus a changed sender number is a re-consent trigger in many compliance reviews — confirm with counsel; not a legal opinion).
4. **Order of re-enable.** Deploy `send-sms-outbox` v7 (fail-closed secret, breaker, stale guard, daily cap) → set `OUTBOX_SECRET` → re-enable job 13, then job 9, then job 10 → watch `sms_outbox` for one day with `OUTBOX_DAILY_CAP=2`.
5. **Dependency note.** `verify-phone` uses Twilio **Verify** (a different product and SID). If the account is replaced rather than reactivated, phone verification for new family members also needs the new provider; Supabase Auth phone OTP is the drop-in alternative and is already configured for admin OTP (`admin_phone_otp_and_growth` migration, 2026-06-26).

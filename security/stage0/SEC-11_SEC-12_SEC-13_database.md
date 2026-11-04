# Level B package — Venuewise database: SEC-11, SEC-12, SEC-13

Project: `urwnbskrtoplgnkkxuvl` · Prepared 2026-11-04 · **Status: AWAITING APPROVAL — nothing applied**

## SEC-11 — seven SECURITY DEFINER views readable by `anon` bypass RLS

### Current defect (VERIFIED live, 2026-11-04, read-only test as role `anon`)

| Query as `anon` | Rows returned |
| --- | --- |
| `select count(*) from public.leads` (table, RLS on) | 0 |
| `select count(*) from public.lead_worklist` (view over `leads`) | **20** |
| `select count(*) from public.sms_outbox` (table, RLS on) | 0 |
| `select count(*) from public.sms_delivery_health` (view over `sms_outbox`, `family_members`) | **7** |
| `gifted_subscriptions` (over `families`, `people`, `subscriptions`) | 0 (no gifted rows today — exposure is structural) |
| `creative_funnel` (over `ad_creatives`, `page_views`, `signup_attribution`) | 0 today |

The views are owned by `postgres` and run with the owner's privileges, so anyone holding the public anon key can read every lead (name, email, phone, message) and the SMS delivery ledger (phone numbers) without logging in. `public_events`, `public_this_week`, `public_upcoming` are intended to be public; the other four are internal reporting views.

### Exact change

```sql
-- SEC-11a: internal views become invoker-rights and are withdrawn from anon.
alter view public.lead_worklist        set (security_invoker = true);
alter view public.creative_funnel      set (security_invoker = true);
alter view public.gifted_subscriptions set (security_invoker = true);
alter view public.sms_delivery_health  set (security_invoker = true);
revoke select on public.lead_worklist, public.creative_funnel,
                 public.gifted_subscriptions, public.sms_delivery_health from anon;
-- authenticated keeps SELECT, but now subject to the base tables' RLS
-- (families/people/subscriptions are scoped by current_family_ids; leads is admin-only).

-- SEC-11b: the three public_* views stay anon-readable but stop bypassing RLS.
-- events and family_events already grant anon SELECT at table level with RLS,
-- so the visible rows are whatever those policies allow — which is the intent.
alter view public.public_events    set (security_invoker = true);
alter view public.public_this_week set (security_invoker = true);
alter view public.public_upcoming  set (security_invoker = true);
```

### Affected apps
- HomeHuddle admin pages that read `lead_worklist` / `sms_delivery_health` while signed in as an admin: continue to work **only if** the admin's session passes the base-table RLS. `leads` policies grant SELECT to admins via `admin_users`; verify with the validation below before approving SEC-11a.
- Public event pages (`public_events`, `public_this_week`, `public_upcoming`): no change expected — validated below.

### Backup
`select pg_get_viewdef(v::regclass, true), v from unnest(array['public.lead_worklist','public.creative_funnel','public.gifted_subscriptions','public.sms_delivery_health','public.public_events','public.public_this_week','public.public_upcoming']) v;` — stored in the PR before applying.

### Validation (run after applying)
```sql
set local role anon;
select count(*) from public.public_upcoming;            -- expected: same count as before the change
select count(*) from public.lead_worklist;              -- expected: ERROR permission denied
reset role;
-- as an admin user's JWT (via the app): lead_worklist returns the leads; via a non-admin JWT it returns 0.
```

### Rollback
`alter view … set (security_invoker = false); grant select on … to anon;` for each view (restores the exposure).

### Risk
Low. Column lists and view bodies are untouched. The only behavioural change is that reads are now subject to RLS.

---

## SEC-12 — three SECURITY DEFINER functions executable by `anon`

### Current defect (VERIFIED live)

| Function | anon EXECUTE | What it does |
| --- | --- | --- |
| `enqueue_internal_alert(p_kind text, p_event_ref text, p_message text)` | yes | Inserts an internal alert that becomes an SMS to the operator |
| `escalate_stale_leads()` | yes | Rewrites lead status and enqueues alerts (cron job 11 calls it daily) |
| `refresh_platform_status()` | yes | Rewrites `platform_status` (cron job 8 every 10 min) |

Anyone with the anon key can flood the operator's phone with alerts (cost + nuisance; blocked today only because Twilio is inactive) or rewrite platform status.

### Exact change
```sql
revoke execute on function public.enqueue_internal_alert(text, text, text) from anon, authenticated, public;
revoke execute on function public.escalate_stale_leads()                   from anon, authenticated, public;
revoke execute on function public.refresh_platform_status()                from anon, authenticated, public;
-- cron jobs run as postgres (job owner) and are unaffected; service_role is unaffected.
```

### Affected apps
None known. `function_edge_logs` for the last 24h show only `send-sms-outbox` and `sync-schedules` traffic; no client calls these RPCs. If a HomeHuddle admin page calls `escalate_stale_leads` directly, it would need to go through an edge function with the service key instead.

### Validation
`select has_function_privilege('anon','public.enqueue_internal_alert(text,text,text)','execute');` → `false`; the next scheduled run of jobs 8 and 11 succeeds (`cron.job_run_details`).

### Rollback
`grant execute on function … to anon, authenticated;`

### Risk
Low.

---

## SEC-13 — no RLS policy references the entitlement model

### Current defect (DOCUMENTED, Phase 2)
`family_product_entitlements` and `recompute_entitlement` exist, but none of the 140 policies consult them: paid access is enforced only in the client. A user with an expired trial and a valid JWT can read and write everything the family policies allow.

### Proposed change (design, not SQL yet)
Add a helper `public.family_has_entitlement(p_family_id uuid, p_product text) returns boolean` (`security definer`, `stable`, `search_path` set) and reference it in the write policies of the premium tables once the product list is confirmed. Which tables are premium is a **product decision** — the CEO confirms the list before SQL is written. Nothing is applied under this heading in this package.

### Risk
Medium if done wrong (locking the owner's own family out). Prepared only after the premium-table list is confirmed.

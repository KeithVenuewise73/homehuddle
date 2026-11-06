# Rinks first release: independent review (Claude)

**Date:** 2026-11-06 · **Branch:** `feat/caz-riverside-booking-transformation`, stacked on `recovery/venuewise-production-2026-11` (PR #2, open, unmerged; head `a3ba3b0`, left unchanged).
**Nothing was applied to any database, nothing deployed, no message sent, nobody charged. Activation stays OFF** (`facilityhuddle/rinks/assets/settings.js` → `enabled:false`).

Labels: **VERIFIED** = run and seen to pass. **DOCUMENTED** = vendor or repo documentation, not re-tested. **NOT VERIFIED** = a launch gate.

## 1. What was reused, changed, or rejected

**Reused from ChatGPT's package (commit `3249d48`, applied unchanged; the patch matched every packaged file):** the two-rink site, the RPC-only design (no direct table grants), the extra tables (cancellation requests, financial dispositions, opening requests, opening list, offer log, facility policies), the trigger that blocks overlapping ice, redacted public output, email sign-in replacing the browser access code, and the `no_channel` honesty for offers.

**Changed (defects found by testing, fixed on this branch):**

| # | Defect | Fix |
| --- | --- | --- |
| 1 | A competing request for the same **new** time stayed `requested` forever after a rival was awarded, and could never be awarded or cleared | `award` closes every pending request for overlapping ice on that sheet |
| 2 | No way to decline or withdraw a request | `decline_rink_request` (rink scheduler), `withdraw_rink_request` (requesting organization), plus buttons |
| 3 | The booking trigger re-validated every update, so cancelling a booking on a since-deactivated sheet failed | A move to `cancelled` is never blocked |
| 4 | A request could be inserted while an award for the same ice was in flight, leaving an orphan pending request | `request_rink_ice` takes the same ice-sheet lock as `award`, in the same lock order |
| 5 | A suspended or archived workspace still granted rink and organization powers | Role checks require `business_workspaces.status = 'active'` |
| 6 | Two calendar writers: the package added its own and left the existing hub writer broken (its default status `'confirmed'` violates the calendar status check; update-then-insert can race) | **Consolidated.** `03_calendar_publisher.sql` repairs `public.publish_to_calendar` (same signature and grants; atomic upsert; default `'active'`), and the rink code calls it. It had no callers (VERIFIED read-only), so nothing existing changes |
| 7 | Awards created bookings with no customer, so the existing staff alert read "Unknown", and schedulers could not see which organization a booking or request belonged to | Award records the organization name. Workspace views (scheduler and that organization only) show it; public views still never do |

**Rejected:** nothing wholesale. The package's claim that the calendar writer was left "unchanged" by design is superseded by #6.

## 2. What was verified, and how

| Suite (all in `tests/rinks/`) | Environment | Result |
| --- | --- | --- |
| `database.test.mjs` (ChatGPT's) | In-process PostgreSQL (PGlite), simplified fixture (columns aligned to production) | PASS |
| `prod_structure.test.mjs` | PGlite, **production-faithful structure**: real columns, NOT NULLs, CHECKs, FKs, RLS posture and the live `bookings_alert` trigger, generated from live catalog metadata (no rows read) | 10 PASS, 2 decision findings (§4) |
| `sessions.test.mjs` | **Real PostgreSQL server, independent connections per person** | 12/12 PASS |
| `browser.e2e.mjs` | Real pages in Chromium (desktop + iPhone 13), real SQL on PostgreSQL; only Supabase Auth/PostgREST simulated | 13/13 PASS |

Locally that server was PostgreSQL 16. The new CI workflow `.github/workflows/rinks-contract-tests.yml` runs all four suites on **PostgreSQL 17** (production's major version) on every PR that touches these files. It uses no secrets and connects to nothing hosted.

**VERIFIED by those suites:**
- **Full sequence:** request → award (real booking + calendar row) → cancellation request (booking stays confirmed; 30-day policy snapshot kept) → approved release (one public opening; financial disposition `undetermined`; `no_channel` offer only to the opted-in other organization) → two competing requests → one award, the other closed → the opening leaves the public page. Exactly one calendar row per booking (original `cancelled`, replacement `active`).
- **Simultaneous awards in independent sessions:** 20/20 rounds for a released opening and 20/20 for overlapping new-time requests gave exactly one booking each time. An interleaved run showed the second session blocked on a row lock (`pg_stat_activity.wait_event_type = 'Lock'`) until the first committed, then refused.
- **Maintenance:** overlapping award, request and direct booking all rejected; the public calendar shows "Unavailable".
- **Unauthorized access** refused for: other organizations, coach and viewer roles, suspended workspaces, renters acting as schedulers, a scheduler of another rink, anonymous callers, direct reads of 9 tables by anon and authenticated, and direct calls to the calendar writer. A non-customer facility cannot receive requests and isn't listed.
- **Revoked membership** takes effect inside an already-open session. A revoked contact gets no opening offer.
- **Redaction:** the anonymous calendar returns only time, sheet and status; openings add a price. No organization names, phone numbers, access codes or amounts appear. Organizations see only their own records and no financial records.
- **Existing production trigger:** every new booking queues exactly one *pending* staff text in `sms_outbox`. Requests, cancellations, releases and offers queue none (§4).
- **Browser:** each step above driven through the actual buttons and forms. Eastern-time entry is stored correctly (6 pm Eastern → 23:00 UTC in November). Official schedule and public-skate links are present on both rinks. No horizontal scrolling at phone width. No JavaScript errors.
- **Live preflight (counts only, read-only):** 0 overlapping bookings, 0 bookings on inactive sheets, 0 invalid times/amounts, 0 name collisions, 0 open slots that would fail the new status check. The only trigger on touched tables is `bookings_alert`. Event triggers are the standard Supabase set.

**Email sign-in:**
- VERIFIED from the project's public auth settings: email sign-in is enabled; sign-ups are open (access still requires an explicit workspace role); phone sign-in uses Twilio Verify, which is inactive.
- DOCUMENTED (Supabase docs): the built-in email sender delivers **only to the project's team members**, at a low hourly limit.
- NOT VERIFIED: whether a custom email provider is configured, and whether the rink page URLs are on the allowed return-URL list. Neither is readable through the tools available to this session.

**Multiple facilities:** there is no exclusive affiliation. An organization requests at any participating rink, and non-participating facilities need no FacilityHuddle record. Calendar source ownership is explicit: FacilityHuddle writes only `('facilityhuddle','bookings',…)` rows, so outside-facility or imported events must use their own source module.

## 3. Launch blockers (activation stays OFF until all are closed)

1. **Recovery PR #2** reviewed and merged (ledger first), then this PR rebased onto `main`.
2. **Test-copy rehearsal on Supabase** (needs CEO approval; may cost): restore the recovered ledger, apply 01→03, run the suites against it, and compare the catalog with production.
3. **Email delivery:** a custom email provider for sign-in links (a vendor choice; may cost), plus the rink page URLs added to the allowed return URLs.
4. **Real rink setup:** facility, ice sheets, rates, resurfacing blocks, cancellation policy (Riverside's is unknown; Cazenovia's 30 days in calendar or business days), authorized schedulers and organization admins.
5. **Content and rights:** the operator name, phone numbers, emails, addresses and the reused hockey photo must be confirmed by the rinks.
6. **Hosting:** which branch GitHub Pages serves for venuewise.net, and the intended rink domains.
7. The two decisions in §4.
8. Promotion of the proposal SQL to versioned migrations through the CEO-approved CI gate (the recovery branch's migration policy).

## 4. Decisions needed (not changed)

- **Staff text on every award.** The existing `bookings_alert` trigger queues a text to active staff alert recipients (1 today) for each new booking; it now names the organization. Nothing sends while Twilio is inactive. Keep it, or exclude rink awards.
- **Price of a released opening.** It defaults to the original renter's booking amount and is shown publicly. Keep it, or use a rink rate.

## 5. Deliberately deferred (unchanged from the package)

Fine-grained opening-list matching and any real notification delivery; roster fan-out to team, family and athlete calendars; HomeHuddle/AthleteHuddle screens; outside-facility event import and duplicate reconciliation; RecTimes migration; recurring series; payments and financial-decision editing; coach self-service.

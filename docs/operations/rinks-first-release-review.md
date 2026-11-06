# Rinks first release — independent review (Claude)

Reviewed 2026-11-06 on top of commit `3249d48` (ChatGPT's package, applied unchanged on `recovery/venuewise-production-2026-11` @ `a3ba3b0`; the patch applied cleanly and every packaged file matched it byte for byte). Nothing was applied to any database, nothing deployed, no messages sent. Activation stays OFF.

## What was run

| Check | Result |
| --- | --- |
| `tests/rinks/database.test.mjs` (ChatGPT's suite, simplified fixture) | PASS, re-run by Claude |
| `tests/rinks/prod_structure.test.mjs` (new): candidate SQL applied to **production-faithful structure**: real columns, NOT NULLs, CHECKs, FKs, RLS-on posture and the live `bookings_alert` trigger, generated from live catalog metadata of `urwnbskrtoplgnkkxuvl` (no rows read) | PASS after the fixes below; 2 findings left for decision |
| Live preflight (counts only): overlapping confirmed/maintenance bookings | 0 |
| Live preflight: bookings on inactive or mismatched areas; invalid time/amount | 0 / 0 |
| Live preflight: name collisions for new schema/tables/functions | 0 |
| `node --check` app.js, api.js | OK |
| Headless browser, both `?rink=` pages, activation off | Renders; no page errors; request view asks to sign in |

## Fixed in this commit

1. **Competing requests for the same new time were left stuck.** Awarding one request only closed rivals on a *published opening*; a rival for the same new time stayed `requested` forever and could never be awarded ("Ice is already reserved"). `award` now closes every pending request on the same ice sheet whose time overlaps the award.
2. **No way to decline or withdraw a request.** Added `decline_rink_request` (rink scheduler) and `withdraw_rink_request` (requesting organization), with wrappers, grants, API entries and buttons.
3. **The new booking trigger could block a release.** `guard_booking` re-validated area/team/overlap on every update, so cancelling a booking whose area had since been deactivated failed. A status change to `cancelled` now always passes.

## Left for CEO / rink decision (not changed)

- **Every award queues a staff text.** The existing production trigger `bookings_alert` fires on any new `bookings` row and queues an SMS to `alert_recipients` (one active recipient today) reading "NEW BOOKING … Unknown … Call: no phone". It is not delivered while Twilio is inactive, but would send once Twilio is reactivated. Options: accept it as the staff alert (and fill `customer_name` with the organization name so it reads properly), or exclude rink-module bookings from that trigger.
- **The released opening publishes the original renter's price.** `decide_cancel` copies `bookings.amount` into `open_slots.price`, which the public page shows. Confirm with each rink whether a negotiated rate may be shown publicly, or use a rink rate card.

## Still not verified (activation gates, unchanged from ChatGPT's list)

Two independent sessions awarding at the same instant (the in-process test database has one connection); Supabase Auth email sign-in and redirect URLs; full recovered-ledger restore and all ~100 production tables/triggers; which branch GitHub Pages serves. Real-world content on the pages (operator "Hasek's Heroes", phone numbers, emails, addresses, official-site links, the reused hockey photo and its rights) must be confirmed by the rinks before anything is published.

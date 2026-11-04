# Venuewise / HomeHuddle — production ledger vs the `homehuddle` repository

Project: `urwnbskrtoplgnkkxuvl` (Venuewise: HomeHuddle, FacilityHuddle, GameTracker, PlayingTime, SMS pipeline)
Ledger source: `supabase_migrations.schema_migrations` (118 rows), exported 2026-11-04, MD5-verified against the live database (see `MANIFEST.csv`).
Repository baseline: `origin/main` @ `c92f003`.

## Headline

**`main` contains no SQL migrations and no edge-function source.** Every branch of the repository was scanned (`git ls-tree` across all `origin/*` refs):

| Branch | `.sql` files | `supabase/functions/` files |
| --- | --- | --- |
| `main` | 0 | 0 |
| `feat/homehuddle-ios-release` | 10 (6 migrations, 1 seed, 3 staging tests) | 5 |
| `claude/playingtime-football-v1-1wy71u` | 4 (standalone PlayingTime schema + tests, not Supabase migrations) | 0 |
| other `claude/*` branches | 0 | 0 |

The 118 applied migrations in this directory are therefore the **only** source for the Venuewise database schema. 112 of them have no counterpart anywhere in the repository.

## `feat/homehuddle-ios-release` migrations vs the ledger

| Branch file | Applied in production? | Match |
| --- | --- | --- |
| 20260810_0001_product_aware_entitlements | Yes — `20260813055855_20260810_0001_product_aware_entitlements` | normalized ratio 0.998 (comment-level) |
| 20260810_0002_founder_slots | Yes — `20260813055935_20260810_0002_founder_slots` | ratio 0.999 |
| 20260810_0003_observability_and_device_tokens | **No** | — |
| 20260810_0004_account_deletion | **No** | — |
| 20260810_0005_admin_read_access | **No** | — |
| 20260810_0006_account_deletion_completion | **No** | — |

Consequence: the iOS-release branch's account-deletion flow (`delete-account`, `hard-delete-worker` functions and migrations 0004/0006), device-token observability (0003) and admin read access (0005) were **never applied to production**. Any plan that assumes those tables exist in production is wrong; the ledger (and the live catalog) are authoritative. This matters for App Store account-deletion compliance and is recorded as an open item, not acted on.

## Ledger composition (118 rows)

| Period | Rows | Content |
| --- | --- | --- |
| 2026-06 | 56 | FacilityHuddle tables, ecosystem bridge links, coach connections, calendar events (conflict/duplicate flags), pg_net + sync cron, SMS consent/outbox/inbound, admin spotlight queue, PII read locks, phone OTP, wave1 (×4) |
| 2026-07 | 17 | wave2 (×7), wave3 forms engine / sandbox / workflow (×6), secure family-member removal, misc |
| 2026-08 | 31 | product-aware entitlements, founder slots, signup attribution RPC, spam controls, public read API, nightly jobs, link/onboarding, hardening |
| 2026-09 | 14 | GameTracker 01–08 (public read API, admin write API, parse-time and change-detection fixes, grant/search_path hardening), site content counts, HomeHuddle sync reports, feed-removal handling, one-text-per-sync, digest wording |

The last applied migration is `20260928200332_homehuddle_digest_wording` (2026-09-28).

## What this directory is and is not

- Verbatim, MD5-verified copies of all 118 applied migrations with original version timestamps and names. Nothing renumbered.
- Not wired into any tooling; must not be applied anywhere. It is an archive and a diff baseline, not a replacement for a `supabase/migrations/` directory (which this repository has never had on `main`).

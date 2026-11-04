<!-- Recovered/written 2026-11-04 on branch recovery/venuewise-production-2026-11. Status: PROPOSED — takes effect when this PR is approved and merged. -->

    # Schema owners — Venuewise / HomeHuddle (`urwnbskrtoplgnkkxuvl`)

    One owner per schema. The owner is the only place a change to that schema may originate. "Production ledger only" means the executed SQL exists nowhere but in the database's own migration ledger — recovered verbatim on 2026-11-04 into `supabase/recovery/production-2026-11/migrations/`.

    | Schema / tables | Product | Source of truth today | Notes |
    | --- | --- | --- | --- |
    | `public — people, families, calendar_events, schedule_change_queue, sms_outbox, sms_inbound, consent` | HomeHuddle core + SMS pipeline | **Production ledger only** (`supabase/recovery/production-2026-11/migrations/`) | No file on `main`. Twilio pipeline is currently failing (account inactive). |
| `public — facilityhuddle_*, athlete_spotlight, submissions, admin_*` | FacilityHuddle | Production ledger only | PII read locks applied 2026-06-25. |
| `public — forms engine (wave3_m1_*)` | Forms engine | Production ledger only |  |
| `public — gametracker_*` | GameTracker | Production ledger only (8 rows, 2026-09-04) |  |
| `public — product entitlements, founder slots` | iOS release | `feat/homehuddle-ios-release` 0001–0002 (applied); 0003–0006 **not applied** | Account deletion / device tokens / admin read never reached production. |
| `public — playingtime (standalone)` | PlayingTime | `claude/playingtime-football-v1-1wy71u` (`playingtime/db/`), not a Supabase migration; also `hlbos_0049_playtime` in HL-BOS Core | Two copies in two projects. Decide one owner before any change. |

    ## Rules

    1. A schema has exactly one owning product. A product that needs another product's tables goes through that product's API (RPC, view or edge function), never by writing migrations into another owner's schema.
    2. "Production ledger only" is a defect to be closed, not a permanent state: the owner's next migration PR must first commit the recovered rows for that schema into the owner's `supabase/migrations/` **unchanged** (same version stamp, same body) so the repo ledger and the database ledger agree. Until then, nothing new is applied to that schema.
    3. Duplicated schemas across projects (`jobscout` ×2, PlayingTime ×2, HLVS v1 vs `vstudio`) get a single owner decision recorded in `docs/architecture/decisions/` before either copy changes.
    4. Changing this table is a PR to this file with the reason stated in the PR body.

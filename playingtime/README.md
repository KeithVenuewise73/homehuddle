# PlayingTime Football — V1

**Know exactly how much your athlete played — and what they did while they were on the field.**

Powered by Venuewise · Built by Herman Legacy Digital · Marketed by 5-Star Sports Media

A parent sits in the stands and taps once per play. PlayingTime counts their
athlete's snaps, works out the participation percentage, and keeps the
statistics — for the game and for the season.

---

## Running it

It is a static site with no build step. Open `index.html` through any web server:

```
npx http-server . -p 8080     # then visit http://localhost:8080/playingtime/
```

Served in production from this repository at **`/playingtime/`**.
The intended public home is `playingtime.venuewise.net`; pointing that subdomain
at this path is a DNS change, and it is the account owner's to make.

## Running the tests

```
node playingtime/tests/run-all.mjs
```

Three suites, all of which actually run:

| Suite | What it proves |
| --- | --- |
| `tests/*.test.js` | The engine's arithmetic and the store's durability, including the failure paths. 51 checks, `node --test`. |
| `tests/acceptance.mjs` | The V1 acceptance list (brief §31), driven through the real app in Chromium at phone size. 74 checks. |
| `tests/db/run.sh` | The schema applies to a real Postgres 16, enforces isolation between two parents, and reverses cleanly. 30 checks. Skipped when no Postgres is reachable. |

The acceptance run writes screenshots to `tests/screens/`.

---

## How it is built

### Local-first, deliberately

The authoritative copy of a live game is **on the device**, written synchronously
on every tap.

This is not a shortcut around the database. It is the design. A parent tracks
from inside a concrete stadium where the signal is usually gone by the second
quarter, and product principle §35 is *look at the field → tap → look back at the
field*. A tracker that needs a network round trip per tap is a tracker that loses
the game.

Cloud sync is an additive layer on top of that, and it is **not switched on** —
see *Where the database is* below.

### Event-sourced, per brief §26

Nothing stores totals. The app stores plays and stat events, and derives every
number on read:

```
{ type: 'play',  unit, quarter, athleteIn }
{ type: 'stat',  unit, quarter, athleteIn, statId, yards }
{ type: 'score', quarter, side, points }
```

Participation, per-quarter splits, season aggregates and the share card all come
out of `engine.js` folding that log. This is what makes undo trivial, makes
correction possible, and means quarter-by-quarter and trend analysis can be added
later without a migration.

Every event carries the context that was true when it happened, so nothing has to
be reconstructed by replaying UI state.

### Files

```
index.html              app shell — one page, hash routing, no reload mid-game
manifest.json  sw.js    installable to a home screen; the shell works offline
assets/css/app.css      one stylesheet; target sizes drive the layout
assets/js/
  catalog.js            units, quarters, positions, statistics, position filtering
  engine.js             pure derivation — every number the product shows
  store.js              localStorage persistence, the event log, undo, export
  sync.js               the honest status of cloud sync
  sharecard.js          the shareable game card, drawn to canvas
  app.js                views, routing, the live game screen
db/                     the Supabase schema — written, verified, UNAPPLIED
tests/                  the three suites above
```

`catalog.js`, `engine.js` and `store.js` have no DOM dependency, which is why the
tests import them directly under `node --test`.

---

## Decisions worth knowing about

**The game screen is built once and updated in place.** A parent taps NEXT PLAY
sixty times a game. Re-rendering on each tap puts a visible stutter between the
tap and the count.

**The bottom navigation is hidden during a live game.** Five nav targets next to
NEXT PLAY is five ways to mis-tap out of the game with a cold thumb. The game
screen has its own menu (☰) instead. Nothing is lost either way — game state is
persisted on every change.

**There is no "special teams play" stat button**, even though the brief lists one
(§11). Special-teams plays are already counted by NEXT PLAY on the special-teams
unit; a second button for the same thing would double-count.

**Passing is COMPLETE / INCOMPLETE, not attempt-then-completion.** One tap per
play, and attempts are derived as completions + incompletions. Two taps to record
one throw is two taps too many at live speed.

**Yardage can be skipped.** The quick sheet (§12) offers `-5 -2 0 2 5 10 15 20`,
a custom keypad, and **Record without yards**. A parent who did not see the gain
still gets the attempt counted, and reports say *"+3 yds (2/3 entered)"* rather
than quietly averaging in a zero.

**A stat with no events reads as absent, not as zero.** Reports list what the
athlete did. A wall of zeroes is noise, and an empty report says so in words.

**One game is in progress at a time.** Two would make "resume" ambiguous and let
a parent record plays against the wrong game without noticing.

**A finished game can be reopened.** Mistakes get noticed when the report is read,
not during the fourth quarter.

---

## Where the database is

`db/0001_playingtime.sql` is written, verified against a real Postgres 16, and
**has not been applied to any database.**

That is deliberate. Applying a migration is the account owner's decision, and the
Supabase project this would target (Venuewise Platform, `urwnbskrtoplgnkkxuvl`)
is not reachable from the environment this was built in.

The schema is additive: it creates a `playingtime` schema and touches nothing in
`public`. RLS is enabled **and forced** on all seven owned tables, every policy is
ownership-scoped, and no policy grants anything to anonymous visitors.

`db/0001_playingtime_down.sql` reverses it.

**Until it is applied, Settings says so, in those words.** There is no "Sync now"
button, because there is nothing on the other end of one. Export data in Settings
produces a real backup file, and that is the honest alternative offered in its
place.

### One bug worth recording

The first version of the schema exposed `game_units` as an ordinary view. A
Postgres view runs with its **owner's** permissions, and the owner is not subject
to RLS — so any signed-in parent could have read the participation of every other
parent's child through it. The migration comment even claimed the opposite.

`tests/db/verify.sql` caught it on the first run. The fix is
`with (security_invoker = true)`, and the check that found it is still in the
suite.

---

## What V1 does not do

Team rosters, video, live score feeds, league or Hudl integration, wearables,
recruiting, GPS, coach playbooks — all out of scope by brief §32. Coaches,
statisticians and whole-roster tracking come after V1 validates.

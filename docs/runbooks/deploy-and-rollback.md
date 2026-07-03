# Runbook — Deploy, Preview & Rollback (Venuewise Core)

This is the safety net that turns "every push is instantly live" into a controlled, reversible process. **These steps are performed by you on GitHub/Supabase** — Claude does not have (and should not have) push access to the repo or the ability to change Pages settings. Claude produces the artifacts; you apply them.

## A. One-time setup (do this in Milestone 1, before any change)

### A1. Confirm how the site deploys today ⚠️ OPEN QUESTION
In GitHub → **Settings → Pages**, note the **Source**: which branch (e.g. `main` / `master` / `gh-pages`) and folder (`/` root or `/docs`) is served. Everything below depends on this. *(This is the one fact Claude could not read without repo access.)*

### A2. Create a `live` branch = current production
```bash
git checkout main            # or whatever A1 shows is the current Pages source
git pull
git checkout -b live
git push -u origin live
```
Then in **Settings → Pages**, set the **Source branch to `live`**. From now on:
- `live` = exactly what's in production.
- Day-to-day work happens on `main`/feature branches (NOT served).
- Production changes only when you **promote** to `live` (Section B).

### A3. Take a database backup + policy snapshot
- Supabase → **Database → Backups**: confirm daily backups are on; trigger a manual backup now. (Or `pg_dump` via the connection string.)
- The RLS policy baseline is already captured in `docs/security/rls-baseline.md`.

### A4. (Optional) Stand up a preview
Two options:
- **GitHub Pages preview:** keep a second branch `preview` bound to a separate Pages site (or a Netlify/Cloudflare Pages project pointed at the repo) so you can smoke-test a candidate before promoting.
- **Supabase preview branch:** Supabase supports database branches for testing schema changes safely. ⚠️ **This has a cost** — do not create one until you've reviewed pricing and explicitly decide to. It is optional and only needed once we start applying migrations (Wave 1+).

## B. Promotion (how a change goes live)
```bash
# 1. Work + review on a feature branch, merged into main
# 2. Smoke-test the candidate (against preview if available)
cd tests && BASE_URL=<preview-or-main-url> npm run test:smoke   # must be green
# 3. Promote to production
git checkout live
git merge --ff-only main        # fast-forward only: live is always a clean pointer
git push origin live            # <-- this is the live deploy
# 4. Immediately re-run smoke against production
cd tests && npm run test:smoke:prod   # must still be green
```

## C. Rollback (if anything looks wrong)
Because `live` is just a pointer, rollback is one command:
```bash
git checkout live
git reset --hard <previous-known-good-SHA>
git push --force origin live    # production instantly reverts to the prior state
```
Keep the last known-good SHA noted before every promotion. Rolling back the site does **not** touch the database — DB changes have their own rollback (Section D).

## D. Database rollback (Wave 1+)
- Every schema change ships as a reversible migration with a paired **down-migration**.
- Early waves are **additive only** — rollback = drop the new object (no data loss, since new objects hold no legacy data).
- Never alter/drop a legacy column in the same release that adds its replacement.
- Points of no return (dropping legacy tables, `NOT NULL workspace_id`, tightening RLS, switching auth enforcement) are each gated behind this checklist + a verified backup.

## E. Pre-change checklist (run before every promotion)
- [ ] Backup verified within last 24h
- [ ] Smoke suite green on the candidate
- [ ] Change is additive & reversible (or gated as a point-of-no-return)
- [ ] Last known-good SHA recorded
- [ ] `venuewise.net/homehuddle/` loads and a calendar renders
- [ ] Rollback command ready to paste

# RLS Security Baseline — Venuewise Platform (production)

**Captured:** Wave 0, Milestone 1, by read-only query of `pg_policies` on project `urwnbskrtoplgnkkxuvl`.
**Purpose:** The documented "before" state VPS §11 requires. This is a **baseline, not a change** — nothing here is modified in Milestone 1. Any hardening is a later, separately-approved milestone.

## Overall posture
RLS is enabled on every `public` table. The authenticated-user model is reasonably mature: most family/athlete data is gated by helper functions `current_family_ids(bool)`, `current_family_emails()`, and `is_admin()`, with a `service_role` bypass for Edge Functions. Public content is exposed via `published = true` / `status = 'published'` read policies. That is a sound core.

The gaps are concentrated in three areas below. None is an emergency (this is normal for a public intake site), but each is documented now so we harden deliberately and never regress.

## Finding 1 — Broad anonymous INSERT on intake tables
Anyone holding the (public-by-design) anon key can insert arbitrary rows into these tables; the policy check is simply `true`:

`academy_applications, academy_mentor_inquiries, academy_parent_permissions, analytics_data, athlete_spotlight_submissions, clinic_registrations, coach_spotlight_submissions, facility_spotlight_submissions, family_players, game_coverage_tips, game_day_photos, leads, legends_spotlight_submissions, organization_spotlight_submissions, page_views, players, player_teams, story_submissions, team_spotlight_submissions`

This is expected for public forms, but it is open to spam/abuse. **Do not tighten yet** — several live pages depend on these anonymous inserts, so tightening without migrating those pages would break production. Hardening options for a later wave: move inserts behind an Edge Function with validation/rate-limiting, add a lightweight hCaptcha/honeypot (note `athlete_spotlight_submissions.hp_field` already exists as a honeypot), or scope inserts by workspace once tenancy lands.

## Finding 2 — Redundant duplicate policies (tech debt)
Several tables carry two identical anon-insert policies (harmless but confusing, and they should be de-duplicated during the hardening wave):
- `family_players`: `Allow public insert on family_players` **and** `anon_insert_family_players`
- `player_teams`: `Allow public insert on player_teams` **and** `anon_insert_player_teams`
- `players`: `Allow public insert on players` **and** `anon_insert_players`
- `coach_spotlight_submissions`: `anon_insert_coach_subs` **and** `anon_insert_spotlight`
- `organization_spotlight_submissions`: `anon_insert_org_spotlight` **and** `anon_insert_org_subs`

## Finding 3 — One likely-broken policy + RLS-enabled tables with no policies
- **`coach_connections`** policy `coach_connections_access` compares `auth.uid()::text = families.id::text`. A family id is not an auth user id, so this predicate almost certainly never matches — the policy is likely dead. Flag for review (not urgent; the table is empty today).
- Several RLS-enabled tables have **no policies at all**, which means everything except `service_role` is denied (they are reached only via Edge Functions). This is fine **if intended**, but should be confirmed per table during the tenancy wave, e.g.: `admin_users`, `bookings`, `facilities`, `facility_areas`, `facility_events`, `open_slots`, `calendar_events`, `calendar_event_participants`, `academy_members`, `_leagueapps_uid_backup`. If any of these is read directly by a page with the anon key today, that page would be failing silently — worth a spot-check in the smoke pass.

## Baseline hardening plan (later waves — NOT now)
1. Keep this document as the "before" snapshot.
2. During the tenancy wave, add `workspace_id` and introduce membership-based policies **alongside** existing ones.
3. During the contract stage, de-duplicate policies (Finding 2), fix/remove the dead policy (Finding 3), and move risky anonymous inserts (Finding 1) behind validated Edge Functions.
4. Re-run this inventory after every policy change and diff against this baseline.

## Reproduce this baseline
```sql
select schemaname, tablename, policyname, cmd, roles::text,
       coalesce(qual,'') as using_expr, coalesce(with_check,'') as check_expr
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;
```
Read-only; safe to run anytime.

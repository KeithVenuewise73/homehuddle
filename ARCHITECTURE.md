# Venuewise Core — Architecture

**Venuewise Core** is the shared, multi-tenant coordination platform that powers Herman Legacy Group businesses, the Huddle products, and future partner organizations. Branded experiences on the surface; one platform underneath. *Powered by Venuewise.*

This repository is evolving — additively and without downtime — from the HomeHuddle site into Venuewise Core, governed by the **Venuewise Platform Specification (VPS) v1.0** in [`/docs`](./docs/README.md).

## Prime directive
HomeHuddle production is Priority #1. Every change is **additive, reversible, and invisible to end users** until proven. `venuewise.net` and `/homehuddle/` do not change during this evolution. Work proceeds in small, reviewable milestones with approval between each.

## Repository layout
Existing product folders are **unchanged** (URL stability). Platform code is layered alongside:

```
/                      HomeHuddle root pages (index, calendar, login, join, account, …) — UNCHANGED
/homehuddle/           HomeHuddle app (+ mirrors) — UNCHANGED, path preserved
/coacheshuddle/  /organizationhuddle/  /facilityhuddle/  /venuewise-admin/  /admin/   — UNCHANGED

/playingtime/          NEW — PlayingTime Football (V1). Self-contained product; adopts nothing existing.
/shared/               NEW — reusable engine client modules (config.js today). Opt-in; adopted per page.
/platform/             NEW — Venuewise platform plane (cross-workspace admin + reporting). Empty scaffold.
/workspaces/           NEW — per-workspace branded entry points (config-driven). Empty scaffold.
/docs/                 NEW — governing specs + runbooks + security baseline.
ARCHITECTURE.md        NEW — this file.
```

## How the platform is built
- **Engines, not products.** Capabilities (Identity, Calendar, Payments, Messaging, Reviews, …) live once in `/shared` + Edge Functions; apps compose them. (VPS §3)
- **One Core, many Workspaces.** Tenancy is logical — `workspace_id` + RLS — introduced additively in later waves. (VPS §2, §4)
- **Configuration over custom code.** New brands/industries/businesses are data (workspaces, branding, industry packs), not forks. (VPS Principle 3, §5)

## Products built on this repository
- **HomeHuddle** — `/`, `/homehuddle/`. Production. Unchanged.
- **CoachesHuddle / OrganizationHuddle / FacilityHuddle** — unchanged.
- **PlayingTime Football** — `/playingtime/`. V1, self-contained and local-first: it
  reads no existing page, imports no existing module, and its Supabase schema
  (`playingtime/db/0001_playingtime.sql`) is written and verified but **unapplied**,
  so it adds nothing to the live database. Zero effect on HomeHuddle. See
  [`playingtime/README.md`](./playingtime/README.md).

## Current status — Wave 0 (Platform Foundation)
- **M1 — Safety Baseline** ✅ smoke suite + RLS baseline + deploy/rollback runbook. No production change.
- **M2 — Platform scaffold** ✅ this scaffold: `/shared` (+ `config.js`), `/platform`, `/workspaces`, `/docs`. **Adopted by nothing — zero behavior change.**
- Next: adopt `config.js` on one page (verify, then the rest), then Wave 1 tenancy tables (additive).

## For future build sessions
Read `/docs` first (VPS → Master Architecture → Phase 1). Never regress HomeHuddle. Never move existing product paths. Migrate one consumer at a time, verify against the smoke suite, and keep every step reversible.

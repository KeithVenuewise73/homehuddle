# `/docs` — Venuewise Core documentation

Home for the governing platform documents and operational runbooks.

## Governing documents (the canonical stack)
1. **Venuewise Platform Specification (VPS) v1.0** — the constitutional document. Everything references it.
2. **Master Architecture v1.0** — the engine + workspace + wave blueprint.
3. **Phase 1 — Architecture & Safety Plan** — the grounded current-state audit.

> Place the three approved documents in this folder so every build session works from one location. Order of authority: VPS → Master Architecture → Phase 1.

## Operational docs (from Wave 0, Milestone 1)
- `security/rls-baseline.md` — documented "before" RLS policy state (do not regress).
- `runbooks/deploy-and-rollback.md` — `live`-branch promotion + one-command rollback.

## Working rules (from the VPS)
- HomeHuddle production is Priority #1; never destabilize it.
- Every change is additive, reversible, and invisible to users until proven.
- Configuration over custom code; shared engines over per-product logic.
- Work in small, reviewable milestones; stop for approval between them.

## Milestone log
- **Wave 0 · M1 — Safety Baseline:** smoke suite, RLS baseline, deploy/rollback runbook. No production change.
- **Wave 0 · M2 — Platform scaffold:** `/shared` (+ `config.js`), `/platform`, `/workspaces`, `/docs`, this index, root `ARCHITECTURE.md`. Additive; adopted by nothing.

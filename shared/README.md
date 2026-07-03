# `/shared` — Venuewise Core engine clients

Thin, reusable JavaScript modules that every branded page/app calls instead of talking to Supabase directly. This is the client side of the platform's engines (VPS §3).

## Adoption policy (important)
**Additive and opt-in.** Adding a module here changes nothing on its own. A page only benefits once it is *explicitly migrated* to use the module, and pages migrate **one at a time**, each verified against the smoke suite before and after. Until migrated, a page keeps its existing inline logic. This is how we refactor a live product without risk.

## Present today (Milestone 2)
- `config.js` — single source of truth for the Supabase URL + anon key. Adopted by **zero** pages yet. First real adoption happens in a later milestone (migrate one page, verify, then the rest).

## Planned modules (later waves, per VPS §3 / Master Architecture wave order)
- Wave 1: `identity.js`, `roles.js`, `workspace.js`
- Wave 2: `calendar.js`, `notifications.js`
- Wave 3: `scheduling.js`, `messaging.js`, `crm.js`, `forms.js`, `documents.js`
- Wave 4: `payments.js`, `reviews.js`
- Wave 5: `media.js`, `analytics.js`, `marketplace.js`
- Wave 6: `workflow.js`, `ai.js`

## Contract
Each module exposes a small, stable function surface (e.g. `calendar.listEvents(workspaceId, range)`), wraps Supabase/Edge-Function calls, and is workspace-aware once tenancy lands. Pages consume the surface, never each other's internals (VPS Principle 7 — API First).

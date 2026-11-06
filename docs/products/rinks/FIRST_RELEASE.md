# Cazenovia + Riverside: the first bite

## Scope
Two public rink websites plus a booking transformation inside the existing Venuewise platform. The broader WNY hockey lifecycle remains a future expansion. This branch does not create a new backend, change the live sites, migrate RecTimes data, send messages or charge anyone.

## Implemented on this branch
- New static site: facilityhuddle/rinks/index.html, selected by ?rink=cazenovia or ?rink=riverside. Shared accessible navigation, rink branding, official schedule links, directions, public calendar and open-ice listings.
- Shared API adapter reuses VW.createClient from shared/config.js, with no new keys. All booking reads/writes use scoped RPCs. Email sign-in replaces the browser access-code approach for these new pages; no legacy page is modified.
- Organization schedulers request time or an exact published opening, see requests and reservations, and request cancellation. Multiple facilities per organization/team are supported without an exclusive affiliation table.
- Facility schedulers award requests at an agreed price, approve/deny cancellation and review notification outcomes. Award creates a real booking and source-key calendar event; pending cancellation keeps ice reserved; approval releases one public opening and creates an undetermined financial disposition.
- Additive SQL candidates under supabase/proposals/rinks, outside automated migration directories. Role checks require active membership and explicit rink or organization roles. Browser-facing functions return redacted shapes; no direct grants expose booking tables.
- Local PostgreSQL-compatible contract tests with synthetic data, including authorization/isolation and booking lifecycle assertions.

## First-release limits
Activation is off in assets/settings.js. The production schema is unchanged. Partner IDs, real teams and accounts are not invented or seeded. No commercial arrangement is implied by a directory entry or page.

The opening list records organization interest in every released slot at the selected facility. Fine-grained matching and real provider delivery are deferred. Attempts honestly record no_channel. Confirmation messages also need a later durable provider outbox; users see booking status in the workspace.

Calendar records are prepared inside the existing calendar_events table; family/athlete screen adoption and roster participant fan-out are deferred. Existing HomeHuddle calendars are unchanged. External-facility events must remain supported in that later integration and must never be treated as FacilityHuddle-controlled reservations.

Bookings are published through the existing calendar hub writer, public.publish_to_calendar, repaired in 03_calendar_publisher.sql (it had no callers; its default status violated the calendar status check and its update-then-insert could race). There is one calendar writer, keyed by (source_module, source_table, source_id). FacilityHuddle owns only ('facilityhuddle','bookings',…) rows; imported or manually entered outside-facility events must use their own source module and are never written or overwritten by FacilityHuddle. Matching an outside event to a FacilityHuddle booking (duplicate reconciliation) is a later slice.

Pending cancellation policy display preserves a policy snapshot and asks for scheduler interpretation; it does not calculate an unverified business-day/calendar-day rule. Financial decisions are recorded as undetermined and handled outside this release; no payment actions exist. Recurring series creation, bulk rescheduling and automated refunds are deferred.

## Before activation
1. Review/merge the production recovery ledger separately; confirm the actual GitHub Pages source branch and intended rink-domain hosting.
2. Promote reviewed candidate SQL into proper CLI-generated migrations, with a recovery/rollback package and CI environment gate. Run the full recovered schema in a Supabase test copy; validate catalog differences and existing triggers.
3. Run the browser flow against that test copy using rink scheduler, org administrator and unauthorized accounts. Test simultaneous awards in independent database sessions. Local embedded PostgreSQL tests do not prove this concurrency property.
4. Confirm each rink's policy, full reservation/resurfacing periods, booking prices and authorized administrators. Resolve email delivery and redirect configuration without exposing credentials.
5. Onboard actual facility, area, workspace and organization/team records through a reviewed process. Reconcile an imported sample week with the rink scheduler before any RecTimes cutover.
6. Obtain CEO approval for the exact release and deploy through CI. Activation is a separate reviewed config change; retain the current official schedule until cutover is verified.

## Review scope
Feature branch is based on recovery/venuewise-production-2026-11 and should be reviewed as a stacked PR against that branch. No AI merges it. Legacy access-code pages remain unchanged and must not be used as the new rink workspace; retiring/replacing those links requires a later explicit cutover.

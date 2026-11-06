# Cazenovia + Riverside: first release candidate

NOT APPLIED. These are proposed SQL changes, intentionally outside the migration runner. The recovered production ledger must be approved/merged first. Promote reviewed scripts to timestamped migrations using the Supabase CLI, then rehearse against a Supabase test copy before CEO-approved CI deployment. No production changes or messages are authorized by these files.

First bite: two public rink sites; public availability; authenticated organization ice requests; scheduler award; cancellation request and release approval; opted-in opening interests and truthful no-channel notification records. Existing bookings/open_slots/calendar_events remain authoritative. No separate backend.

Deferred: provider delivery, RecTimes import, recurring series creation, payments/credits, broad WNY rollout, family/athlete UI integration, nonparticipating facility schedule entry, coach self-service. Organization administrators can request ice across any participating facilities; no exclusive facility affiliation is required.

Apply candidate order in a test copy: 01_schema.sql, 02_functions.sql, 03_calendar_publisher.sql (03 repairs the existing unattached public.publish_to_calendar, which 02 now calls; see docs/operations/rinks-first-release-review.md). A live overlap preflight, grants review, full recovered-ledger restore and concurrent-session test are rollout gates. Local fixture tests are explicitly not a substitute for that rehearsal.

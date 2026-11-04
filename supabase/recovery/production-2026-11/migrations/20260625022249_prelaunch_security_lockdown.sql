
-- 1) Enable RLS on the 9 unprotected tables (deny-all for anon/authenticated;
--    service_role and SECURITY DEFINER RPCs still work).
alter table public._leagueapps_uid_backup       enable row level security;
alter table public.bookings                      enable row level security;
alter table public.calendar_event_participants   enable row level security;
alter table public.calendar_events               enable row level security;
alter table public.coach_connections             enable row level security;
alter table public.facilities                    enable row level security;
alter table public.facility_areas                enable row level security;
alter table public.facility_events               enable row level security;
alter table public.open_slots                    enable row level security;

-- 2) Strip the over-broad anon/authenticated grants on those tables (defense in depth).
revoke all on
  public._leagueapps_uid_backup, public.bookings, public.calendar_event_participants,
  public.calendar_events, public.coach_connections, public.facilities,
  public.facility_areas, public.facility_events, public.open_slots
from anon, authenticated;

-- 3) Sensitive / internal SECURITY DEFINER views: fully revoke public API access.
--    (family_events_by_email leaked every family's events+emails to anon.)
revoke all on
  public.family_events_by_email, public.sync_summary,
  public.this_week, public.upcoming_events
from anon, authenticated;

-- 4) Genuinely public spotlight views (team-level, no child names): keep READ,
--    remove write privileges.
revoke insert, update, delete, truncate, references, trigger on
  public.public_events, public.public_this_week, public.public_upcoming
from anon, authenticated;

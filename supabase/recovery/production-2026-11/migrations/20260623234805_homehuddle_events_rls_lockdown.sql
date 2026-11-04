-- ============================================================================
-- Lock down the synced sports-schedule `events` table.
-- Was world-readable (Public read events / anon_read_events using=true) plus
-- anon insert/update. Replace with: authenticated users may SELECT only events
-- whose feed belongs to one of their families (feeds.email in current_family_emails()).
-- Writes remain service_role-only (the sync function). No browser writes to events.
-- ============================================================================

-- remove anon/public holes
DROP POLICY IF EXISTS "Public read events"  ON public.events;
DROP POLICY IF EXISTS "anon_read_events"    ON public.events;
DROP POLICY IF EXISTS "anon_insert_events"  ON public.events;
DROP POLICY IF EXISTS "anon_update_events"  ON public.events;
-- keep "Service write events" (service_role ALL)

-- authenticated read, scoped to the user's families' feeds
DROP POLICY IF EXISTS auth_events_select ON public.events;
CREATE POLICY auth_events_select ON public.events
  FOR SELECT TO authenticated
  USING (
    feed_id IN (
      SELECT f.id FROM public.feeds f
      WHERE f.email IN (SELECT public.current_family_emails())
    )
  );
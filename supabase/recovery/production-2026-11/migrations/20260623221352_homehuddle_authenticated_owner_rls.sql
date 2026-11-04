-- Owner-scoped read/write for the AUTHENTICATED role on HomeHuddle's tables.
-- Fixes the logged-in calendar (which reads as 'authenticated', not 'anon')
-- AND is the real lockdown: you see a family's data only if you have an
-- active family_access row for it. Anon policies are LEFT in place for now so
-- the old ?email= calendar keeps working; they get removed at cutover.

-- Helper: the family_ids the current logged-in person may access.
CREATE OR REPLACE FUNCTION public.current_family_ids(p_editable boolean DEFAULT false)
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT fa.family_id
  FROM public.family_access fa
  JOIN public.people p ON p.id = fa.person_id
  WHERE p.auth_user_id = auth.uid()
    AND fa.status = 'active'
    AND (NOT p_editable OR fa.can_edit = true);
$$;
REVOKE ALL ON FUNCTION public.current_family_ids(boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.current_family_ids(boolean) TO authenticated;

-- Helper: the family emails (feeds/reminders/push key on email, not family_id).
CREATE OR REPLACE FUNCTION public.current_family_emails()
RETURNS SETOF text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT f.email FROM public.families f
  WHERE f.id IN (SELECT public.current_family_ids(false)) AND f.email IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.current_family_emails() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.current_family_emails() TO authenticated;

-- families: read your own family
DROP POLICY IF EXISTS auth_families_select ON public.families;
CREATE POLICY auth_families_select ON public.families FOR SELECT TO authenticated
  USING (id IN (SELECT public.current_family_ids(false)));

-- family_events: read own; write only where you can_edit
DROP POLICY IF EXISTS auth_family_events_select ON public.family_events;
CREATE POLICY auth_family_events_select ON public.family_events FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(false)));
DROP POLICY IF EXISTS auth_family_events_insert ON public.family_events;
CREATE POLICY auth_family_events_insert ON public.family_events FOR INSERT TO authenticated
  WITH CHECK (family_id IN (SELECT public.current_family_ids(true)));
DROP POLICY IF EXISTS auth_family_events_update ON public.family_events;
CREATE POLICY auth_family_events_update ON public.family_events FOR UPDATE TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(true)))
  WITH CHECK (family_id IN (SELECT public.current_family_ids(true)));
DROP POLICY IF EXISTS auth_family_events_delete ON public.family_events;
CREATE POLICY auth_family_events_delete ON public.family_events FOR DELETE TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(true)));

-- family_members: read own family's roster
DROP POLICY IF EXISTS auth_family_members_select ON public.family_members;
CREATE POLICY auth_family_members_select ON public.family_members FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(false)));

-- feeds: read + update (theme) by family email
DROP POLICY IF EXISTS auth_feeds_select ON public.feeds;
CREATE POLICY auth_feeds_select ON public.feeds FOR SELECT TO authenticated
  USING (email IN (SELECT public.current_family_emails()));
DROP POLICY IF EXISTS auth_feeds_update ON public.feeds;
CREATE POLICY auth_feeds_update ON public.feeds FOR UPDATE TO authenticated
  USING (email IN (SELECT public.current_family_emails()))
  WITH CHECK (email IN (SELECT public.current_family_emails()));

-- reminders: read + dismiss(update) by family email
DROP POLICY IF EXISTS auth_reminders_select ON public.reminders;
CREATE POLICY auth_reminders_select ON public.reminders FOR SELECT TO authenticated
  USING (email IN (SELECT public.current_family_emails()));
DROP POLICY IF EXISTS auth_reminders_update ON public.reminders;
CREATE POLICY auth_reminders_update ON public.reminders FOR UPDATE TO authenticated
  USING (email IN (SELECT public.current_family_emails()))
  WITH CHECK (email IN (SELECT public.current_family_emails()));

-- push_subscriptions: read/insert/update by family email
DROP POLICY IF EXISTS auth_push_select ON public.push_subscriptions;
CREATE POLICY auth_push_select ON public.push_subscriptions FOR SELECT TO authenticated
  USING (email IN (SELECT public.current_family_emails()));
DROP POLICY IF EXISTS auth_push_insert ON public.push_subscriptions;
CREATE POLICY auth_push_insert ON public.push_subscriptions FOR INSERT TO authenticated
  WITH CHECK (email IN (SELECT public.current_family_emails()));
DROP POLICY IF EXISTS auth_push_update ON public.push_subscriptions;
CREATE POLICY auth_push_update ON public.push_subscriptions FOR UPDATE TO authenticated
  USING (email IN (SELECT public.current_family_emails()))
  WITH CHECK (email IN (SELECT public.current_family_emails()));

-- Tighten function grants the advisor flagged (API-callable SECURITY DEFINER).
REVOKE EXECUTE ON FUNCTION public.verify_and_link(text, uuid, text) FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.handle_phone_auth_user() FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.get_merged_calendar(timestamptz, timestamptz) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.get_merged_calendar(timestamptz, timestamptz) TO authenticated;
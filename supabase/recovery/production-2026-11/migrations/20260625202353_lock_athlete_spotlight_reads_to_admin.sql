
-- Replace the "any authenticated user can read" policy with admin-only.
-- Public nominate-form INSERT stays; the admin queue reads via the gated RPC.
DROP POLICY IF EXISTS auth_read_athlete_subs ON public.athlete_spotlight_submissions;
CREATE POLICY admin_read_athlete_subs ON public.athlete_spotlight_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

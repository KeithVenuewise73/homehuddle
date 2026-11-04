
-- academy_submissions: was read+write+delete for ANY logged-in user. No page uses it.
DROP POLICY IF EXISTS auth_all_submissions ON public.academy_submissions;
CREATE POLICY admin_read_academy_submissions ON public.academy_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

-- interview_records: same broad ALL policy. Editorial data, admin-only.
DROP POLICY IF EXISTS auth_all_interviews ON public.interview_records;
CREATE POLICY admin_read_interview_records ON public.interview_records
  FOR SELECT TO authenticated USING (public.is_admin());

-- Hardening: pin search_path on the 5 flagged functions (no behavior change).
ALTER FUNCTION public.generate_slug(text) SET search_path = public;
ALTER FUNCTION public.refresh_platform_status() SET search_path = public;
ALTER FUNCTION public.set_article_slug() SET search_path = public;
ALTER FUNCTION public.sync_homehuddle_events_to_calendar() SET search_path = public;
ALTER FUNCTION public.trg_subscriptions_updated_at() SET search_path = public;

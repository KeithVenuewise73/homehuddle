
-- Lock READS on all public submission/registration tables to admins only.
-- Public INSERT (the submission forms) is left untouched, so forms keep working.
-- No page currently reads these, so nothing breaks.

-- clinic registrations (was anon-readable by the whole internet)
DROP POLICY IF EXISTS anon_read_registrations ON public.clinic_registrations;
CREATE POLICY admin_read_clinic_registrations ON public.clinic_registrations
  FOR SELECT TO authenticated USING (public.is_admin());

-- academy applications / permissions / mentor inquiries / assignments
DROP POLICY IF EXISTS auth_read_applications ON public.academy_applications;
CREATE POLICY admin_read_academy_applications ON public.academy_applications
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS auth_read_permissions ON public.academy_parent_permissions;
CREATE POLICY admin_read_academy_permissions ON public.academy_parent_permissions
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS auth_read_mentors ON public.academy_mentor_inquiries;
CREATE POLICY admin_read_academy_mentors ON public.academy_mentor_inquiries
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS anon_read_assignments ON public.academy_assignments;
DROP POLICY IF EXISTS auth_read_assignments ON public.academy_assignments;
CREATE POLICY admin_read_academy_assignments ON public.academy_assignments
  FOR SELECT TO authenticated USING (public.is_admin());

-- 5-Star spotlight submission tables (submitter contact info)
DROP POLICY IF EXISTS auth_read_coach_subs ON public.coach_spotlight_submissions;
DROP POLICY IF EXISTS anon_read_spotlight ON public.coach_spotlight_submissions;
CREATE POLICY admin_read_coach_subs ON public.coach_spotlight_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS auth_read_team_subs ON public.team_spotlight_submissions;
CREATE POLICY admin_read_team_subs ON public.team_spotlight_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS auth_read_org_subs ON public.organization_spotlight_submissions;
DROP POLICY IF EXISTS anon_read_org_spotlight ON public.organization_spotlight_submissions;
CREATE POLICY admin_read_org_subs ON public.organization_spotlight_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS auth_read_facility_subs ON public.facility_spotlight_submissions;
CREATE POLICY admin_read_facility_subs ON public.facility_spotlight_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS auth_read_legends_subs ON public.legends_spotlight_submissions;
CREATE POLICY admin_read_legends_subs ON public.legends_spotlight_submissions
  FOR SELECT TO authenticated USING (public.is_admin());

-- game coverage tips
DROP POLICY IF EXISTS auth_read_game_tips ON public.game_coverage_tips;
CREATE POLICY admin_read_game_tips ON public.game_coverage_tips
  FOR SELECT TO authenticated USING (public.is_admin());

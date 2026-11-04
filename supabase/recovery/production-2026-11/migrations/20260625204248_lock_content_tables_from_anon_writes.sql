
-- Remove anonymous create/edit on 5-Star directory content.
-- No app page writes these (content is managed via service role); public READ stays.

-- clinics
DROP POLICY IF EXISTS anon_insert_clinics ON public.clinics;
DROP POLICY IF EXISTS anon_update_clinics ON public.clinics;

-- coaches
DROP POLICY IF EXISTS anon_insert_coaches ON public.coaches;
DROP POLICY IF EXISTS anon_update_coaches ON public.coaches;

-- organizations
DROP POLICY IF EXISTS anon_insert_orgs ON public.organizations;
DROP POLICY IF EXISTS anon_update_orgs ON public.organizations;

-- organization events
DROP POLICY IF EXISTS anon_insert_org_events ON public.organization_events;
DROP POLICY IF EXISTS anon_update_org_events ON public.organization_events;

-- organization join tables (junk-link creation)
DROP POLICY IF EXISTS anon_insert_org_athletes ON public.organization_athletes;
DROP POLICY IF EXISTS anon_insert_org_coaches ON public.organization_coaches;

-- analytics: keep anon INSERT (page-view tracking), remove anon UPDATE (tampering)
DROP POLICY IF EXISTS anon_update_analytics ON public.analytics_data;

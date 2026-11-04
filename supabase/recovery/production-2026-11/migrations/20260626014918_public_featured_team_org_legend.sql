
-- TEAM
CREATE OR REPLACE FUNCTION public.public_featured_team()
RETURNS TABLE(team_name text, age_group text, organization text, coach text,
  season_record text, notable_achievements text, why_special text, photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT team_name, age_group, organization, coach, season_record, notable_achievements, why_special, photo_url
  FROM public.team_spotlight_submissions
  WHERE status = 'published' ORDER BY created_at DESC LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.public_featured_team() FROM public;
GRANT EXECUTE ON FUNCTION public.public_featured_team() TO anon, authenticated;

-- ORGANIZATION
CREATE OR REPLACE FUNCTION public.public_featured_organization()
RETURNS TABLE(organization_name text, sport text, founded text, location text,
  website text, mission text, number_of_athletes text, why_feature text, logo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT organization_name, sport, founded, location, website, mission,
         number_of_athletes, why_feature, logo_url
  FROM public.organization_spotlight_submissions
  WHERE status = 'published' ORDER BY created_at DESC LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.public_featured_organization() FROM public;
GRANT EXECUTE ON FUNCTION public.public_featured_organization() TO anon, authenticated;

-- LEGEND (no email/phone exposed)
CREATE OR REPLACE FUNCTION public.public_featured_legend()
RETURNS TABLE(nominee_name text, business_profession text, company text, sports_played text,
  community_involvement text, why_feature text, community_impact text, photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT nominee_name, business_profession, company, sports_played, community_involvement,
         why_feature, community_impact, photo_url
  FROM public.legends_spotlight_submissions
  WHERE status = 'published' ORDER BY created_at DESC LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.public_featured_legend() FROM public;
GRANT EXECUTE ON FUNCTION public.public_featured_legend() TO anon, authenticated;

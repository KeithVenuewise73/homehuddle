
-- Public read for the CURRENT featured coach: the most recent "published" coach spotlight.
-- Returns ONLY public-safe fields (no email/phone). Returns 0 rows if none published yet.
CREATE OR REPLACE FUNCTION public.public_featured_coach()
RETURNS TABLE(
  coach_name text, organization text, sports_coached text, years_coaching text,
  coaching_philosophy text, community_impact text, why_feature text, biography text, photo_url text
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coach_name, organization, sports_coached, years_coaching,
         coaching_philosophy, community_impact, why_feature, biography, photo_url
  FROM public.coach_spotlight_submissions
  WHERE status = 'published'
  ORDER BY created_at DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.public_featured_coach() FROM public;
GRANT EXECUTE ON FUNCTION public.public_featured_coach() TO anon, authenticated;

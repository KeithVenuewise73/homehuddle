-- Returns the caller's family players (kids) eligible for an athlete profile,
-- with whether they already have one. Used by the AthleteHuddle onboarding UI.
CREATE OR REPLACE FUNCTION public.my_athlete_candidates()
RETURNS TABLE (player_id uuid, player_name text, family_id uuid, family_name text, has_profile boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT p.id, p.name, fam.id, fam.family_name,
         EXISTS (SELECT 1 FROM public.athlete_player_links apl WHERE apl.player_id = p.id) AS has_profile
  FROM public.family_players fp
  JOIN public.players  p   ON p.id  = fp.player_id
  JOIN public.families fam ON fam.id = fp.family_id
  WHERE fp.family_id IN (SELECT public.current_family_ids(true))
  ORDER BY fam.family_name, p.name;
$$;

REVOKE ALL ON FUNCTION public.my_athlete_candidates() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_athlete_candidates() TO authenticated;

-- Lists the signed-in family's athlete profiles (with public status) for the hub.
CREATE OR REPLACE FUNCTION public.my_athletes()
RETURNS TABLE(id uuid, first_name text, last_name text, graduation_year int,
              school text, primary_sport text, secondary_sports text[],
              profile_photo_url text, city text, state text, is_public boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT a.id, a.first_name, a.last_name, a.graduation_year, a.school,
         a.primary_sport, a.secondary_sports, a.profile_photo_url, a.city, a.state,
         coalesce(a.is_public, false)
  FROM public.athletes a
  WHERE a.family_id IN (SELECT public.current_family_ids(false))
  ORDER BY a.first_name, a.last_name;
$$;

REVOKE ALL ON FUNCTION public.my_athletes() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.my_athletes() TO authenticated;

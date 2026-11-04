
-- 1) Owner toggles an athlete profile public/private (the "Push to 5-Star" action).
CREATE OR REPLACE FUNCTION public.set_athlete_public(p_athlete_id uuid, p_public boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_family uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT family_id INTO v_family FROM public.athletes WHERE id = p_athlete_id;
  IF v_family IS NULL THEN RAISE EXCEPTION 'athlete_not_found'; END IF;
  IF v_family NOT IN (SELECT public.current_family_ids(true)) THEN
    RAISE EXCEPTION 'no_edit_access_to_athlete';
  END IF;
  UPDATE public.athletes SET is_public = coalesce(p_public, false) WHERE id = p_athlete_id;
  RETURN jsonb_build_object('athlete_id', p_athlete_id, 'is_public', coalesce(p_public, false));
END; $$;

-- 2) Public read of ONE athlete card — only if the parent has made it public.
--    Deliberately omits: family_id, birthdate, coach names, and any calendar/whereabouts.
CREATE OR REPLACE FUNCTION public.public_athlete_card(p_athlete_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'id', a.id,
    'first_name', a.first_name,
    'last_name', a.last_name,
    'graduation_year', a.graduation_year,
    'gender', a.gender,
    'city', a.city,
    'state', a.state,
    'profile_photo_url', a.profile_photo_url,
    'primary_sport', a.primary_sport,
    'secondary_sports', a.secondary_sports,
    'height_inches', a.height_inches,
    'weight_lbs', a.weight_lbs,
    'dominant_hand', a.dominant_hand,
    'dominant_foot', a.dominant_foot,
    'school', a.school,
    'sports', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'sport', s.sport, 'position', s.position, 'current_team', s.current_team,
        'organization', s.organization, 'season', s.season) ORDER BY s.created_at)
      FROM public.athlete_sports s
      WHERE s.athlete_id = a.id AND coalesce(s.is_active, true)), '[]'::jsonb),
    'stats', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'sport', st.sport, 'stat_name', st.stat_name, 'stat_value', st.stat_value, 'season', st.season)
        ORDER BY st.recorded_at)
      FROM public.athlete_stats st
      WHERE st.athlete_id = a.id), '[]'::jsonb)
  )
  FROM public.athletes a
  WHERE a.id = p_athlete_id AND a.is_public = true;
$$;

-- 3) Public directory of all opted-in athlete cards (for a 5-Star players index).
CREATE OR REPLACE FUNCTION public.public_athlete_directory()
RETURNS TABLE(id uuid, first_name text, last_name text, graduation_year int,
              primary_sport text, city text, state text, school text, profile_photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id, first_name, last_name, graduation_year, primary_sport, city, state, school, profile_photo_url
  FROM public.athletes
  WHERE is_public = true
  ORDER BY graduation_year NULLS LAST, last_name, first_name;
$$;

-- 4) Submit a profile for a 5-Star Spotlight -> editorial queue (admin dashboard).
--    Owner-only, requires explicit permission, pulls core facts from the real profile.
CREATE OR REPLACE FUNCTION public.submit_athlete_spotlight(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_athlete uuid := (p_payload->>'athlete_id')::uuid;
  a public.athletes;
  v_sub uuid;
  v_perm boolean := coalesce((p_payload->>'permission_confirmed')::boolean, false);
  v_sports text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF v_athlete IS NULL THEN RAISE EXCEPTION 'missing_athlete_id'; END IF;
  SELECT * INTO a FROM public.athletes WHERE id = v_athlete;
  IF a.id IS NULL THEN RAISE EXCEPTION 'athlete_not_found'; END IF;
  IF a.family_id NOT IN (SELECT public.current_family_ids(true)) THEN
    RAISE EXCEPTION 'no_edit_access_to_athlete';
  END IF;
  IF v_perm IS NOT TRUE THEN RAISE EXCEPTION 'permission_required'; END IF;

  v_sports := coalesce(a.primary_sport, '')
    || coalesce(' / ' || nullif(array_to_string(a.secondary_sports, ', '), ''), '');

  INSERT INTO public.athlete_spotlight_submissions (
    athlete_name, age, school, graduation_year, sports, position, team_organization,
    parent_name, parent_email, parent_phone, athlete_email, city,
    achievements, awards, community_service, favorite_memory, future_goals,
    photo_url, additional_photos, why_feature, permission_confirmed, status
  ) VALUES (
    trim(coalesce(a.first_name,'') || ' ' || coalesce(a.last_name,'')),
    nullif(p_payload->>'age',''),
    a.school, a.graduation_year, nullif(v_sports,''),
    p_payload->>'position', p_payload->>'team_organization',
    p_payload->>'parent_name', p_payload->>'parent_email', p_payload->>'parent_phone',
    p_payload->>'athlete_email', a.city,
    p_payload->>'achievements', p_payload->>'awards', p_payload->>'community_service',
    p_payload->>'favorite_memory', p_payload->>'future_goals',
    a.profile_photo_url, p_payload->>'additional_photos', p_payload->>'why_feature',
    true, 'new'
  ) RETURNING id INTO v_sub;

  RETURN jsonb_build_object('submission_id', v_sub, 'status', 'new');
END; $$;

-- Grants: public read for the card + directory; authenticated-only for the writes.
REVOKE ALL ON FUNCTION public.set_athlete_public(uuid, boolean) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.set_athlete_public(uuid, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_athlete_spotlight(jsonb) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.submit_athlete_spotlight(jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.public_athlete_card(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_athlete_directory() TO anon, authenticated;


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
        'organization', s.organization, 'season', s.season)
        ORDER BY coalesce(s.is_active, true) DESC, s.created_at)
      FROM public.athlete_sports s
      WHERE s.athlete_id = a.id), '[]'::jsonb),
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

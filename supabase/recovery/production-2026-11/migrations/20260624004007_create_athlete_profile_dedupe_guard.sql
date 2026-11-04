CREATE OR REPLACE FUNCTION public.create_athlete_profile(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth     uuid := auth.uid();
  v_family   uuid := (p_payload->>'family_id')::uuid;
  v_player   uuid := NULLIF(p_payload->>'player_id','')::uuid;
  a          jsonb := p_payload->'athlete';
  v_athlete  uuid;
  v_public   boolean := coalesce((a->>'is_public')::boolean, false);
  v_secondary text[];
  sp         jsonb;
BEGIN
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF v_family IS NULL OR a IS NULL OR coalesce(a->>'first_name','') = '' THEN
    RAISE EXCEPTION 'missing_required_fields';
  END IF;
  IF v_family NOT IN (SELECT public.current_family_ids(true)) THEN
    RAISE EXCEPTION 'no_edit_access_to_family';
  END IF;

  IF v_player IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.family_players WHERE family_id = v_family AND player_id = v_player) THEN
      RAISE EXCEPTION 'player_not_in_family';
    END IF;
    IF EXISTS (SELECT 1 FROM public.athlete_player_links WHERE player_id = v_player) THEN
      RAISE EXCEPTION 'player_already_has_profile';
    END IF;
  END IF;

  IF jsonb_typeof(a->'secondary_sports') = 'array' THEN
    SELECT array_agg(value) INTO v_secondary
    FROM jsonb_array_elements_text(a->'secondary_sports') AS value;
  END IF;

  INSERT INTO public.athletes (
    family_id, first_name, last_name, birthdate, graduation_year, gender,
    city, state, profile_photo_url, primary_sport, secondary_sports,
    height_inches, weight_lbs, dominant_hand, dominant_foot, school, is_public
  ) VALUES (
    v_family, a->>'first_name', a->>'last_name', NULLIF(a->>'birthdate','')::date,
    NULLIF(a->>'graduation_year','')::int, a->>'gender', a->>'city', a->>'state',
    a->>'profile_photo_url', a->>'primary_sport', coalesce(v_secondary,'{}'),
    NULLIF(a->>'height_inches','')::numeric, NULLIF(a->>'weight_lbs','')::numeric,
    a->>'dominant_hand', a->>'dominant_foot', a->>'school', v_public
  ) RETURNING id INTO v_athlete;

  IF v_player IS NOT NULL THEN
    INSERT INTO public.athlete_player_links (athlete_id, player_id) VALUES (v_athlete, v_player);
  END IF;

  IF jsonb_typeof(p_payload->'sports') = 'array' THEN
    FOR sp IN SELECT * FROM jsonb_array_elements(p_payload->'sports') LOOP
      INSERT INTO public.athlete_sports
        (athlete_id, sport, position, current_team, organization, coach_name, season, is_active)
      VALUES (v_athlete, sp->>'sport', sp->>'position', sp->>'current_team',
              sp->>'organization', sp->>'coach_name', sp->>'season', true);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('athlete_id', v_athlete, 'is_public', v_public);
END;
$$;
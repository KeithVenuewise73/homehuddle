-- ============================================================================
-- create_athlete_profile(p_payload jsonb)
-- Creates an AthleteHuddle profile for one of the caller's family players,
-- atomically: athletes row (PRIVATE by default) + optional player link + sports.
-- Enforces: caller can EDIT the family; player (if given) belongs to that family;
-- is_public only true if explicitly passed (the parent's deliberate toggle).
-- returns { athlete_id, is_public }
-- ============================================================================
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

  -- caller must be able to EDIT this family
  IF v_family NOT IN (SELECT public.current_family_ids(true)) THEN
    RAISE EXCEPTION 'no_edit_access_to_family';
  END IF;

  -- if linking a player, it must belong to this family
  IF v_player IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.family_players
      WHERE family_id = v_family AND player_id = v_player
    ) THEN
      RAISE EXCEPTION 'player_not_in_family';
    END IF;
  END IF;

  -- secondary_sports: json array -> text[]
  IF jsonb_typeof(a->'secondary_sports') = 'array' THEN
    SELECT array_agg(value) INTO v_secondary
    FROM jsonb_array_elements_text(a->'secondary_sports') AS value;
  END IF;

  INSERT INTO public.athletes (
    family_id, first_name, last_name, birthdate, graduation_year, gender,
    city, state, profile_photo_url, primary_sport, secondary_sports,
    height_inches, weight_lbs, dominant_hand, dominant_foot, school, is_public
  ) VALUES (
    v_family,
    a->>'first_name',
    a->>'last_name',
    NULLIF(a->>'birthdate','')::date,
    NULLIF(a->>'graduation_year','')::int,
    a->>'gender',
    a->>'city',
    a->>'state',
    a->>'profile_photo_url',
    a->>'primary_sport',
    coalesce(v_secondary, '{}'),
    NULLIF(a->>'height_inches','')::numeric,
    NULLIF(a->>'weight_lbs','')::numeric,
    a->>'dominant_hand',
    a->>'dominant_foot',
    a->>'school',
    v_public
  )
  RETURNING id INTO v_athlete;

  -- link to the HomeHuddle player
  IF v_player IS NOT NULL THEN
    INSERT INTO public.athlete_player_links (athlete_id, player_id)
    VALUES (v_athlete, v_player);
  END IF;

  -- optional sports detail
  IF jsonb_typeof(p_payload->'sports') = 'array' THEN
    FOR sp IN SELECT * FROM jsonb_array_elements(p_payload->'sports') LOOP
      INSERT INTO public.athlete_sports
        (athlete_id, sport, position, current_team, organization, coach_name, season, is_active)
      VALUES (
        v_athlete, sp->>'sport', sp->>'position', sp->>'current_team',
        sp->>'organization', sp->>'coach_name', sp->>'season', true
      );
    END LOOP;
  END IF;

  RETURN jsonb_build_object('athlete_id', v_athlete, 'is_public', v_public);
END;
$$;

REVOKE ALL ON FUNCTION public.create_athlete_profile(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_athlete_profile(jsonb) TO authenticated;
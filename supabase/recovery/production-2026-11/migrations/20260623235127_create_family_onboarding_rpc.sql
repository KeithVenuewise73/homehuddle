-- ============================================================================
-- create_family_onboarding(p_payload jsonb)
-- Secure replacement for join.html's 7 anon table-writes. Runs as the table
-- owner (SECURITY DEFINER) but keys ownership to the INVOKER's auth.uid(), so a
-- new family can be created under the locked-down model (no anon write policies).
-- The caller MUST be authenticated (phone-verified) first.
--
-- payload shape:
-- {
--   "family":  { "name","email","phone","pin","sms_consent","display_name" },
--   "members": [ { "name","role","phone","email","receives_sms","receives_push",
--                  "can_add_events","can_edit_events","is_owner" } ],
--   "players": [ { "name","birth_year","phone","receives_sms",
--                  "teams":[ {"team_name","sport","platform","ical_url","color"} ] } ]
-- }
-- returns: { "family_id": uuid, "email": text }
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_family_onboarding(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth      uuid := auth.uid();
  v_person    uuid;
  v_family    uuid;
  v_fname     text := p_payload->'family'->>'name';
  v_email     text := p_payload->'family'->>'email';
  v_phone     text := p_payload->'family'->>'phone';
  v_pin       text := coalesce(p_payload->'family'->>'pin', '');
  v_consent   boolean := coalesce((p_payload->'family'->>'sms_consent')::boolean, false);
  v_disp      text := coalesce(p_payload->'family'->>'display_name', v_fname);
  m           jsonb;
  pl          jsonb;
  t           jsonb;
  v_player    uuid;
BEGIN
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING HINT = 'Verify your phone before creating a family';
  END IF;
  IF v_fname IS NULL OR v_email IS NULL OR v_phone IS NULL THEN
    RAISE EXCEPTION 'missing_required_family_fields';
  END IF;

  -- Resolve (or create) the creator's person, tied to their auth user.
  SELECT id INTO v_person FROM public.people WHERE auth_user_id = v_auth LIMIT 1;
  IF v_person IS NULL THEN
    SELECT id INTO v_person FROM public.people WHERE phone = v_phone LIMIT 1;
  END IF;
  IF v_person IS NULL THEN
    INSERT INTO public.people (phone, phone_verified, auth_user_id, display_name)
    VALUES (v_phone, true, v_auth, v_disp)
    RETURNING id INTO v_person;
  ELSE
    UPDATE public.people
      SET auth_user_id = v_auth,
          phone_verified = true,
          display_name = COALESCE(display_name, v_disp)
      WHERE id = v_person;
  END IF;

  -- Create the family.
  INSERT INTO public.families (family_name, email, phone, pin, status, sms_consent)
  VALUES (v_fname, v_email, v_phone, v_pin, 'trial', v_consent)
  RETURNING id INTO v_family;

  -- Link the creator as OWNER (editable).
  INSERT INTO public.family_access (person_id, family_id, role, status, can_edit)
  VALUES (v_person, v_family, 'owner', 'active', true);

  -- Adult/household members.
  IF jsonb_typeof(p_payload->'members') = 'array' THEN
    FOR m IN SELECT * FROM jsonb_array_elements(p_payload->'members') LOOP
      INSERT INTO public.family_members
        (family_id, name, role, phone, email, receives_sms, receives_push,
         can_add_events, can_edit_events, is_owner)
      VALUES (
        v_family,
        m->>'name',
        coalesce(m->>'role','parent'),
        m->>'phone',
        m->>'email',
        coalesce((m->>'receives_sms')::boolean, true),
        coalesce((m->>'receives_push')::boolean, true),
        coalesce((m->>'can_add_events')::boolean, false),
        coalesce((m->>'can_edit_events')::boolean, false),
        coalesce((m->>'is_owner')::boolean, false)
      );
    END LOOP;
  END IF;

  -- Players + their teams + feeds.
  IF jsonb_typeof(p_payload->'players') = 'array' THEN
    FOR pl IN SELECT * FROM jsonb_array_elements(p_payload->'players') LOOP
      INSERT INTO public.players (name, birth_year)
      VALUES (pl->>'name', pl->>'birth_year')
      RETURNING id INTO v_player;

      INSERT INTO public.family_players (family_id, player_id, relationship)
      VALUES (v_family, v_player, 'child');

      -- player as a read-only family member
      INSERT INTO public.family_members
        (family_id, name, role, phone, receives_sms, receives_push,
         can_add_events, can_edit_events, is_owner)
      VALUES (
        v_family, pl->>'name', 'player', pl->>'phone',
        coalesce((pl->>'receives_sms')::boolean, false), true,
        false, false, false
      );

      IF jsonb_typeof(pl->'teams') = 'array' THEN
        FOR t IN SELECT * FROM jsonb_array_elements(pl->'teams') LOOP
          INSERT INTO public.player_teams
            (player_id, team_name, sport, platform, ical_url, color, is_active)
          VALUES (
            v_player, t->>'team_name', t->>'sport', t->>'platform',
            t->>'ical_url', t->>'color', true
          );

          IF coalesce(t->>'ical_url','') <> '' THEN
            INSERT INTO public.feeds
              (family_name, email, phone, kid_name, sport, platform,
               ical_url, team_name, is_active, status)
            VALUES (
              v_fname, v_email, v_phone, pl->>'name', t->>'sport',
              coalesce(t->>'platform','manual'), t->>'ical_url',
              t->>'team_name', true, 'trial'
            );
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('family_id', v_family, 'email', v_email);
END;
$$;

-- Lock execute to authenticated callers only (no anon).
REVOKE ALL ON FUNCTION public.create_family_onboarding(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_family_onboarding(jsonb) TO authenticated;
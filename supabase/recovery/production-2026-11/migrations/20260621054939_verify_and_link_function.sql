-- Step 2 — verify_and_link()
-- Called AFTER Twilio Verify confirms a code. In one transaction:
--   1) upsert the people row (mark verified, attach auth user)
--   2) auto-link: one family_access row per family that listed this phone,
--      with role mapped from the roster and can_edit from per-person flags
--   3) back-fill family_members.person_id so identity is anchored to the
--      person, not the phone (survives a future number change)
-- SECURITY DEFINER so it can write despite RLS; EXECUTE restricted to
-- service_role (server-side / edge function), never anon or the browser.

CREATE OR REPLACE FUNCTION public.verify_and_link(
    p_phone         text,
    p_auth_user_id  uuid DEFAULT NULL,
    p_display_name  text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_person_id uuid;
BEGIN
    IF p_phone !~ '^\+[1-9]\d{6,14}$' THEN
        RAISE EXCEPTION 'phone must be E.164 (got %)', p_phone;
    END IF;

    -- 1) Upsert person, mark verified, attach auth user (keep existing if not supplied).
    INSERT INTO public.people (phone, phone_verified, auth_user_id, display_name)
    VALUES (p_phone, true, p_auth_user_id, p_display_name)
    ON CONFLICT (phone) DO UPDATE
        SET phone_verified = true,
            auth_user_id   = COALESCE(EXCLUDED.auth_user_id, public.people.auth_user_id),
            display_name    = COALESCE(EXCLUDED.display_name, public.people.display_name)
    RETURNING id INTO v_person_id;

    -- 2) Auto-link: one row per family that listed this phone.
    INSERT INTO public.family_access (person_id, family_id, role, status, can_edit)
    SELECT
        v_person_id,
        m.family_id,
        CASE
            WHEN bool_or(COALESCE(m.is_owner,false))      THEN 'owner'
            WHEN bool_or(m.role = 'parent')               THEN 'parent'
            WHEN bool_or(COALESCE(m.role,'') <> 'player') THEN 'viewer'
            ELSE 'player'
        END,
        'active',
        bool_or(COALESCE(m.is_owner,false))
          OR bool_or(m.role = 'parent')
          OR bool_or(COALESCE(m.can_add_events,false) OR COALESCE(m.can_edit_events,false))
    FROM public.family_members m
    WHERE m.phone = p_phone
      AND m.family_id IS NOT NULL
    GROUP BY m.family_id
    ON CONFLICT (person_id, family_id) DO NOTHING;

    -- 3) Back-fill roster -> person link for every matched row.
    UPDATE public.family_members
       SET person_id = v_person_id
     WHERE phone = p_phone
       AND person_id IS DISTINCT FROM v_person_id;

    RETURN v_person_id;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_and_link(text, uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.verify_and_link(text, uuid, text) TO service_role;

COMMENT ON FUNCTION public.verify_and_link(text, uuid, text) IS
  'Post-Twilio-Verify: upsert verified person, auto-link family_access for every family that listed the phone, back-fill family_members.person_id. Server-side only.';

-- Roster of approved academy members. Access controlled by the `active` toggle.
CREATE TABLE IF NOT EXISTS public.academy_members (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone       text NOT NULL,                 -- stored normalized (last 10 digits)
  full_name   text NOT NULL,
  role        text NOT NULL DEFAULT 'student',
  active      boolean NOT NULL DEFAULT true,
  notes       text,
  created_at  timestamptz DEFAULT now(),
  created_by  uuid
);
CREATE UNIQUE INDEX IF NOT EXISTS academy_members_phone_uk ON public.academy_members (phone);
ALTER TABLE public.academy_members ENABLE ROW LEVEL SECURITY;
-- No public policies => only SECURITY DEFINER functions / service role can read or write it.

-- Normalize a phone to its last 10 digits (US) for consistent matching.
CREATE OR REPLACE FUNCTION public.norm_phone(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT right(regexp_replace(coalesce(p,''), '\D', '', 'g'), 10);
$$;

-- Is the currently-logged-in caller an ACTIVE academy member?
-- Matches the OTP-verified phone on auth.users against the active roster.
CREATE OR REPLACE FUNCTION public.is_academy_member()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.academy_members m
    JOIN auth.users u ON u.id = auth.uid()
    WHERE m.active
      AND m.phone = public.norm_phone(u.phone)
  );
$$;

-- ── Admin management (all gated by is_admin) ──
CREATE OR REPLACE FUNCTION public.admin_add_academy_member(p_name text, p_phone text, p_role text DEFAULT 'student')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_phone text; v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  v_phone := public.norm_phone(p_phone);
  IF length(v_phone) < 10 THEN RAISE EXCEPTION 'invalid_phone'; END IF;
  INSERT INTO public.academy_members(phone, full_name, role, active, created_by)
  VALUES (v_phone, p_name, coalesce(nullif(p_role,''),'student'), true, auth.uid())
  ON CONFLICT (phone) DO UPDATE SET full_name = excluded.full_name, role = excluded.role, active = true
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'ok', true);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_academy_members()
RETURNS SETOF public.academy_members LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.academy_members WHERE public.is_admin() ORDER BY active DESC, full_name;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_academy_member_active(p_id uuid, p_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  UPDATE public.academy_members SET active = p_active WHERE id = p_id;
  RETURN jsonb_build_object('id', p_id, 'active', p_active, 'ok', true);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_remove_academy_member(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  DELETE FROM public.academy_members WHERE id = p_id;
  RETURN jsonb_build_object('id', p_id, 'removed', true);
END; $$;

REVOKE ALL ON FUNCTION public.is_academy_member() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.is_academy_member() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_add_academy_member(text, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_add_academy_member(text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_academy_members() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_list_academy_members() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_academy_member_active(uuid, boolean) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_set_academy_member_active(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_remove_academy_member(uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_remove_academy_member(uuid) TO authenticated;

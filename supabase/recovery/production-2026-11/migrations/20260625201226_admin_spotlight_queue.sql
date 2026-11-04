
-- Admin allowlist (no RLS policies => only SECURITY DEFINER functions can read it)
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Seed the current admin (5-Star email login)
INSERT INTO public.admin_users (user_id, email)
VALUES ('52fe9f59-52e8-49d1-8b66-083042d7f282', 'kherman7373@gmail.com')
ON CONFLICT (user_id) DO NOTHING;

-- is_admin(): true only for allowlisted users
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid());
$$;

-- Read the spotlight queue — returns rows ONLY to admins, nothing to anyone else
CREATE OR REPLACE FUNCTION public.admin_list_spotlight_submissions()
RETURNS SETOF public.athlete_spotlight_submissions
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.athlete_spotlight_submissions
  WHERE public.is_admin()
  ORDER BY created_at DESC;
$$;

-- Update a submission's workflow fields (admin only)
CREATE OR REPLACE FUNCTION public.admin_update_spotlight(p_id uuid, p_status text, p_reporter text, p_notes text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  UPDATE public.athlete_spotlight_submissions
  SET status = coalesce(nullif(p_status,''), status),
      assigned_reporter = coalesce(p_reporter, assigned_reporter),
      notes = coalesce(p_notes, notes)
  WHERE id = p_id;
  RETURN jsonb_build_object('id', p_id, 'ok', true);
END; $$;

REVOKE ALL ON FUNCTION public.is_admin() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_spotlight_submissions() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_list_spotlight_submissions() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_update_spotlight(uuid, text, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_update_spotlight(uuid, text, text, text) TO authenticated;

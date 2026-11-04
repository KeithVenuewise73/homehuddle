
CREATE OR REPLACE FUNCTION public.admin_delete_spotlight(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
  DELETE FROM public.athlete_spotlight_submissions WHERE id = p_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_delete_spotlight(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_spotlight(uuid) TO authenticated;

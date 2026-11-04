
-- Media-dashboard access = active academy member who is a reporter or mentor (or the admin).
CREATE OR REPLACE FUNCTION public.is_media_member()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.academy_members m
    JOIN auth.users u ON u.id = auth.uid()
    WHERE m.active
      AND m.role IN ('reporter','mentor')
      AND m.phone = public.norm_phone(u.phone)
  ) OR public.is_admin();
$$;

-- Reporter-scoped reads (return rows only to media members)
CREATE OR REPLACE FUNCTION public.media_list_athlete_subs()
RETURNS SETOF public.athlete_spotlight_submissions LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.athlete_spotlight_submissions WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

CREATE OR REPLACE FUNCTION public.media_list_coach_subs()
RETURNS SETOF public.coach_spotlight_submissions LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.coach_spotlight_submissions WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

CREATE OR REPLACE FUNCTION public.media_list_team_subs()
RETURNS SETOF public.team_spotlight_submissions LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.team_spotlight_submissions WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

CREATE OR REPLACE FUNCTION public.media_list_org_subs()
RETURNS SETOF public.organization_spotlight_submissions LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.organization_spotlight_submissions WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

CREATE OR REPLACE FUNCTION public.media_list_facility_subs()
RETURNS SETOF public.facility_spotlight_submissions LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.facility_spotlight_submissions WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

CREATE OR REPLACE FUNCTION public.media_list_legends_subs()
RETURNS SETOF public.legends_spotlight_submissions LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.legends_spotlight_submissions WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

CREATE OR REPLACE FUNCTION public.media_list_game_tips()
RETURNS SETOF public.game_coverage_tips LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT * FROM public.game_coverage_tips WHERE public.is_media_member() ORDER BY created_at DESC LIMIT 200; $$;

-- Reporter status updates (allowlisted tables only)
CREATE OR REPLACE FUNCTION public.media_update_status(p_table text, p_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE allowed text[] := ARRAY['athlete_spotlight_submissions','coach_spotlight_submissions','team_spotlight_submissions',
  'organization_spotlight_submissions','facility_spotlight_submissions','legends_spotlight_submissions','game_coverage_tips'];
BEGIN
  IF NOT public.is_media_member() THEN RAISE EXCEPTION 'not_media'; END IF;
  IF NOT (p_table = ANY(allowed)) THEN RAISE EXCEPTION 'bad_table'; END IF;
  EXECUTE format('UPDATE public.%I SET status = $1 WHERE id = $2', p_table) USING p_status, p_id;
  RETURN jsonb_build_object('ok', true);
END; $$;

DO $g$
DECLARE fn text;
BEGIN
  FOR fn IN SELECT unnest(ARRAY[
    'is_media_member()','media_list_athlete_subs()','media_list_coach_subs()','media_list_team_subs()',
    'media_list_org_subs()','media_list_facility_subs()','media_list_legends_subs()','media_list_game_tips()',
    'media_update_status(text, uuid, text)'])
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM anon, public', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', fn);
  END LOOP;
END $g$;

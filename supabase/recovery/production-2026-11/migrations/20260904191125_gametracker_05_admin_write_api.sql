CREATE OR REPLACE FUNCTION public.gametracker_import(
  p_payload jsonb,
  p_dry_run boolean DEFAULT true,
  p_source  text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized. Sign in as a 5-Star admin to import schedules.'
      USING ERRCODE = '42501';
  END IF;
  RETURN gametracker.import_events(p_payload, p_dry_run, p_source, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_event_admin(p_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
  SELECT CASE WHEN public.is_admin() THEN (
    SELECT to_jsonb(x) FROM (
      SELECT e.*, s.display_name AS sport_name, src.publish AS source_published
      FROM gametracker.events e
      JOIN gametracker.sports  s   ON s.key = e.sport
      JOIN gametracker.sources src ON src.key = e.source
      WHERE e.id = p_id
    ) x)
  END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_update_live(
  p_id           uuid,
  p_status       text    DEFAULT NULL,
  p_home_score   integer DEFAULT NULL,
  p_away_score   integer DEFAULT NULL,
  p_period       text    DEFAULT NULL,
  p_clock        text    DEFAULT NULL,
  p_result_data  jsonb   DEFAULT NULL,
  p_score_source text    DEFAULT 'manual_admin'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
DECLARE
  v_status text;
  v_id     uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized. Sign in as a 5-Star admin to update a score.'
      USING ERRCODE = '42501';
  END IF;

  IF p_status IS NOT NULL THEN
    v_status := gametracker.norm_status(p_status);
    IF v_status IS NULL THEN
      RAISE EXCEPTION 'Unrecognized status "%". Use upcoming, live, final, postponed or cancelled.', p_status;
    END IF;
  END IF;

  IF p_score_source IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM gametracker.sources WHERE key = p_score_source) THEN
    RAISE EXCEPTION 'Unknown score source "%".', p_score_source;
  END IF;

  UPDATE gametracker.events SET
    status       = coalesce(v_status, status),
    home_score   = coalesce(p_home_score, home_score),
    away_score   = coalesce(p_away_score, away_score),
    period       = coalesce(p_period, period),
    clock        = coalesce(p_clock, clock),
    result_data  = coalesce(result_data, '{}'::jsonb) || coalesce(p_result_data, '{}'::jsonb),
    score_source = coalesce(p_score_source, score_source),
    last_synced_at = now()
  WHERE id = p_id
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No GameTracker event with id %', p_id;
  END IF;
  RETURN public.gametracker_event_admin(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_admin_events(
  p_source text    DEFAULT NULL,
  p_date   date    DEFAULT NULL,
  p_sport  text    DEFAULT NULL,
  p_limit  integer DEFAULT 200
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.starts_at)
    FROM (
      SELECT e.id, e.source, e.source_event_id, e.sport, s.display_name AS sport_name,
             e.league, e.level, e.home_team_name, e.away_team_name,
             e.event_date,
             CASE WHEN e.start_time IS NULL THEN NULL
                  ELSE to_char(e.start_time, 'FMHH12:MI AM') END AS start_time,
             e.starts_at, e.venue, e.status, e.home_score, e.away_score,
             e.period, e.clock, e.result_data, e.last_synced_at,
             src.publish AS source_published
      FROM gametracker.events e
      JOIN gametracker.sports  s   ON s.key = e.sport
      JOIN gametracker.sources src ON src.key = e.source
      WHERE (p_source IS NULL OR e.source = p_source)
        AND (p_date   IS NULL OR e.event_date = p_date)
        AND (p_sport  IS NULL OR e.sport = gametracker.slugify(p_sport))
      ORDER BY e.starts_at
      LIMIT greatest(coalesce(p_limit, 200), 1)
    ) x), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_save_source(
  p_key        text,
  p_name       text    DEFAULT NULL,
  p_kind       text    DEFAULT 'schedule',
  p_adapter    text    DEFAULT 'json',
  p_publish    boolean DEFAULT false,
  p_trust_rank integer DEFAULT 100,
  p_notes      text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
DECLARE v_key text := nullif(trim(coalesce(p_key, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  IF v_key IS NULL THEN RAISE EXCEPTION 'A source key is required.'; END IF;

  INSERT INTO gametracker.sources (key, name, kind, adapter, publish, trust_rank, notes)
  VALUES (v_key, coalesce(nullif(trim(coalesce(p_name,'')),''), v_key),
          coalesce(p_kind, 'schedule'), coalesce(p_adapter, 'json'),
          coalesce(p_publish, false), coalesce(p_trust_rank, 100), p_notes)
  ON CONFLICT (key) DO UPDATE SET
    name       = coalesce(nullif(trim(coalesce(p_name,'')),''), gametracker.sources.name),
    kind       = coalesce(p_kind, gametracker.sources.kind),
    adapter    = coalesce(p_adapter, gametracker.sources.adapter),
    publish    = coalesce(p_publish, gametracker.sources.publish),
    trust_rank = coalesce(p_trust_rank, gametracker.sources.trust_rank),
    notes      = coalesce(p_notes, gametracker.sources.notes);

  RETURN (SELECT to_jsonb(s) FROM gametracker.sources s WHERE s.key = v_key);
END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_sources()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.key)
    FROM (
      SELECT s.*,
             (SELECT count(*) FROM gametracker.events e WHERE e.source = s.key) AS event_count
      FROM gametracker.sources s
    ) x), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_link_alias(
  p_alias       text,
  p_school_slug text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
DECLARE
  v_school uuid;
  v_norm   text := gametracker.norm_school(p_alias);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  IF v_norm IS NULL THEN RAISE EXCEPTION 'An alias is required.'; END IF;

  SELECT id INTO v_school FROM gametracker.schools WHERE slug = gametracker.slugify(p_school_slug);
  IF v_school IS NULL THEN
    RAISE EXCEPTION 'No school with slug "%"', p_school_slug;
  END IF;

  INSERT INTO gametracker.school_aliases (alias_norm, school_id, source)
  VALUES (v_norm, v_school, 'admin')
  ON CONFLICT (alias_norm) DO UPDATE SET school_id = EXCLUDED.school_id;

  RETURN jsonb_build_object('ok', true, 'alias', v_norm, 'school_slug', p_school_slug);
END;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_delete_event(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
DECLARE v_n integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM gametracker.events WHERE id = p_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', v_n > 0, 'deleted', v_n);
END;
$$;

GRANT EXECUTE ON FUNCTION public.gametracker_import(jsonb, boolean, text)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_update_live(uuid, text, integer, integer, text, text, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_event_admin(uuid)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_admin_events(text, date, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_save_source(text, text, text, text, boolean, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_sources()                             TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_link_alias(text, text)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_delete_event(uuid)                    TO authenticated;
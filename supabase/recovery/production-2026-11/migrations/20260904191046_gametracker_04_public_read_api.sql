CREATE OR REPLACE FUNCTION public.gametracker_events(
  p_region      text    DEFAULT NULL,
  p_sport       text    DEFAULT NULL,
  p_gender      text    DEFAULT NULL,
  p_league      text    DEFAULT NULL,
  p_section     text    DEFAULT NULL,
  p_school      text    DEFAULT NULL,
  p_status      text    DEFAULT NULL,
  p_season_name text    DEFAULT NULL,
  p_date        date    DEFAULT NULL,
  p_date_from   date    DEFAULT NULL,
  p_date_to     date    DEFAULT NULL,
  p_season      integer DEFAULT NULL,
  p_level       text    DEFAULT NULL,
  p_limit       integer DEFAULT 200,
  p_offset      integer DEFAULT 0
)
RETURNS TABLE (
  id              uuid,
  sport           text,
  sport_name      text,
  base_sport      text,
  sport_season    text,
  scoring_model   text,
  period_label    text,
  period_abbrev   text,
  gender          text,
  level           text,
  league          text,
  league_name     text,
  section         text,
  classification  text,
  season          integer,
  season_phase    text,
  region          text,
  home_team_name  text,
  away_team_name  text,
  home_team_slug  text,
  away_team_slug  text,
  event_name      text,
  participants    jsonb,
  event_date      date,
  start_time      text,
  starts_at       timestamptz,
  timezone        text,
  venue           text,
  status          text,
  home_score      integer,
  away_score      integer,
  period          text,
  clock           text,
  result_data     jsonb,
  source          text,
  last_synced_at  timestamptz
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
  WITH params AS (
    SELECT
      nullif(trim(coalesce(p_region, '')), '')                    AS region,
      nullif(gametracker.slugify(coalesce(p_sport, '')), '')      AS sport,
      nullif(lower(trim(coalesce(p_gender, ''))), '')             AS gender,
      nullif(gametracker.slugify(coalesce(p_league, '')), '')     AS league,
      nullif(upper(trim(coalesce(p_section, ''))), '')            AS section,
      nullif(gametracker.norm_school(coalesce(p_school, '')), '') AS school,
      nullif(lower(trim(coalesce(p_status, ''))), '')             AS view,
      nullif(lower(trim(coalesce(p_season_name, ''))), '')        AS season_name,
      nullif(lower(trim(coalesce(p_level, ''))), '')              AS level,
      (now() AT TIME ZONE 'America/New_York')::date               AS today
  )
  SELECT
    e.id, e.sport, s.display_name, s.base_sport, s.season, s.scoring_model,
    s.period_label, s.period_abbrev,
    e.gender, e.level, e.league, l.name, e.section, e.classification,
    e.season, e.season_phase, e.region,
    e.home_team_name, e.away_team_name, hs.slug, aws.slug,
    e.event_name, e.participants,
    e.event_date,
    CASE WHEN e.start_time IS NULL THEN NULL
         ELSE to_char(e.start_time, 'FMHH12:MI AM') END,
    e.starts_at, e.timezone, e.venue,
    e.status, e.home_score, e.away_score, e.period, e.clock, e.result_data,
    e.source, e.last_synced_at
  FROM gametracker.events e
  JOIN gametracker.sports  s   ON s.key = e.sport
  JOIN gametracker.sources src ON src.key = e.source
  LEFT JOIN gametracker.leagues l   ON l.key = e.league
  LEFT JOIN gametracker.schools hs  ON hs.id = e.home_team_id
  LEFT JOIN gametracker.schools aws ON aws.id = e.away_team_id
  CROSS JOIN params p
  WHERE src.publish = true
    AND (p.region      IS NULL OR e.region ILIKE p.region)
    AND (p.sport       IS NULL OR e.sport = p.sport OR s.base_sport = p.sport)
    AND (p.gender      IS NULL OR e.gender = p.gender)
    AND (p.league      IS NULL OR e.league = p.league)
    AND (p.section     IS NULL OR upper(coalesce(e.section, l.section, '')) = p.section)
    AND (p.level       IS NULL OR e.level = p.level)
    AND (p.season_name IS NULL OR s.season = p.season_name)
    AND (p_season      IS NULL OR e.season = p_season)
    AND (p.school      IS NULL
         OR hs.name_norm = p.school OR aws.name_norm = p.school
         OR hs.slug = gametracker.slugify(p.school) OR aws.slug = gametracker.slugify(p.school)
         OR gametracker.norm_school(e.home_team_name) = p.school
         OR gametracker.norm_school(e.away_team_name) = p.school)
    AND (p_date      IS NULL OR e.event_date = p_date)
    AND (p_date_from IS NULL OR e.event_date >= p_date_from)
    AND (p_date_to   IS NULL OR e.event_date <= p_date_to)
    AND (
      p.view IS NULL OR p.view IN ('all', 'any')
      OR (p.view = 'live'      AND e.status = 'live')
      OR (p.view = 'upcoming'  AND e.status = 'upcoming' AND e.starts_at >= now() - interval '4 hours')
      OR (p.view IN ('final', 'results') AND e.status = 'final')
      OR (p.view = 'today'     AND e.event_date = p.today)
      OR (p.view = 'tonight'   AND e.event_date = p.today
                               AND (e.start_time IS NULL OR e.start_time >= time '16:00'))
      OR (p.view = 'postponed' AND e.status IN ('postponed', 'suspended'))
      OR (p.view = 'cancelled' AND e.status = 'cancelled')
      OR (p.view NOT IN ('live','upcoming','final','results','today','tonight',
                         'postponed','cancelled','all','any')
          AND e.status = p.view)
    )
  ORDER BY
    CASE e.status
      WHEN 'live'      THEN 0
      WHEN 'upcoming'  THEN 1
      WHEN 'suspended' THEN 2
      WHEN 'postponed' THEN 2
      WHEN 'final'     THEN 3
      ELSE 4
    END,
    CASE WHEN e.status = 'final'
         THEN -extract(epoch FROM e.starts_at)
         ELSE  extract(epoch FROM e.starts_at) END,
    e.sport, e.home_team_name
  LIMIT greatest(coalesce(p_limit, 200), 1)
  OFFSET greatest(coalesce(p_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION public.gametracker_event(p_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
  SELECT to_jsonb(x) FROM (
    SELECT e.id, e.sport, s.display_name AS sport_name, s.base_sport,
           s.scoring_model, s.period_label, s.period_abbrev,
           e.gender, e.level, e.league, l.name AS league_name, e.section,
           e.classification, e.season, e.season_phase, e.region,
           e.home_team_name, e.away_team_name, hs.slug AS home_team_slug,
           aws.slug AS away_team_slug, e.event_name, e.participants,
           e.event_date,
           CASE WHEN e.start_time IS NULL THEN NULL
                ELSE to_char(e.start_time, 'FMHH12:MI AM') END AS start_time,
           e.starts_at, e.timezone, e.venue, e.status,
           e.home_score, e.away_score, e.period, e.clock, e.result_data,
           e.source, e.last_synced_at
    FROM gametracker.events e
    JOIN gametracker.sports  s   ON s.key = e.sport
    JOIN gametracker.sources src ON src.key = e.source
    LEFT JOIN gametracker.leagues l   ON l.key = e.league
    LEFT JOIN gametracker.schools hs  ON hs.id = e.home_team_id
    LEFT JOIN gametracker.schools aws ON aws.id = e.away_team_id
    WHERE src.publish = true AND e.id = p_id
  ) x;
$$;

CREATE OR REPLACE FUNCTION public.gametracker_filters(
  p_region text    DEFAULT NULL,
  p_season integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
  WITH visible AS (
    SELECT e.*
    FROM gametracker.events e
    JOIN gametracker.sources src ON src.key = e.source
    WHERE src.publish = true
      AND (p_region IS NULL OR e.region ILIKE p_region)
      AND (p_season IS NULL OR e.season = p_season)
  )
  SELECT jsonb_build_object(
    'total_events', (SELECT count(*) FROM visible),
    'live_count',   (SELECT count(*) FROM visible WHERE status = 'live'),
    'today_count',  (SELECT count(*) FROM visible
                      WHERE event_date = (now() AT TIME ZONE 'America/New_York')::date),
    'date_range',   (SELECT jsonb_build_object('min', min(event_date), 'max', max(event_date)) FROM visible),
    'last_synced',  (SELECT max(last_synced_at) FROM visible),
    'sports', coalesce((
      SELECT jsonb_agg(x ORDER BY x ->> 'sort_order', x ->> 'display_name')
      FROM (
        SELECT DISTINCT jsonb_build_object(
                 'key', s.key, 'display_name', s.display_name,
                 'base_sport', s.base_sport, 'gender', s.gender,
                 'season', s.season, 'scoring_model', s.scoring_model,
                 'sort_order', lpad(s.sort_order::text, 5, '0'),
                 'count', (SELECT count(*) FROM visible v2 WHERE v2.sport = s.key)) AS x
        FROM gametracker.sports s
        WHERE EXISTS (SELECT 1 FROM visible v WHERE v.sport = s.key)
      ) t), '[]'::jsonb),
    'leagues', coalesce((
      SELECT jsonb_agg(x ORDER BY x ->> 'sort_order', x ->> 'name')
      FROM (
        SELECT DISTINCT jsonb_build_object(
                 'key', l.key, 'name', l.name, 'section', l.section,
                 'sort_order', lpad(l.sort_order::text, 5, '0'),
                 'count', (SELECT count(*) FROM visible v2 WHERE v2.league = l.key)) AS x
        FROM gametracker.leagues l
        WHERE EXISTS (SELECT 1 FROM visible v WHERE v.league = l.key)
      ) t), '[]'::jsonb),
    'seasons', coalesce((
      SELECT jsonb_agg(DISTINCT season ORDER BY season DESC) FROM visible), '[]'::jsonb),
    'season_names', coalesce((
      SELECT jsonb_agg(DISTINCT s.season)
      FROM visible v JOIN gametracker.sports s ON s.key = v.sport), '[]'::jsonb),
    'schools', coalesce((
      SELECT jsonb_agg(x ORDER BY x ->> 'name')
      FROM (
        SELECT DISTINCT jsonb_build_object('slug', sc.slug, 'name', sc.name) AS x
        FROM gametracker.schools sc
        WHERE EXISTS (SELECT 1 FROM visible v
                      WHERE v.home_team_id = sc.id OR v.away_team_id = sc.id)
      ) t), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.gametracker_school(
  p_slug   text,
  p_season integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
  WITH sc AS (
    SELECT * FROM gametracker.schools
    WHERE slug = gametracker.slugify(p_slug)
       OR name_norm = gametracker.norm_school(p_slug)
    LIMIT 1
  ), ev AS (
    SELECT e.id, e.sport, s.display_name AS sport_name, e.gender, e.level,
           e.league, e.home_team_name, e.away_team_name, e.event_date,
           CASE WHEN e.start_time IS NULL THEN NULL
                ELSE to_char(e.start_time, 'FMHH12:MI AM') END AS start_time,
           e.starts_at, e.venue, e.status, e.home_score, e.away_score,
           e.period, e.clock, e.result_data, e.source,
           (e.home_team_id = sc.id) AS is_home,
           (now() AT TIME ZONE 'America/New_York')::date AS today
    FROM gametracker.events e
    JOIN gametracker.sports  s   ON s.key = e.sport
    JOIN gametracker.sources src ON src.key = e.source
    CROSS JOIN sc
    WHERE src.publish = true
      AND (e.home_team_id = sc.id OR e.away_team_id = sc.id)
      AND (p_season IS NULL OR e.season = p_season)
  )
  SELECT CASE WHEN (SELECT count(*) FROM sc) = 0 THEN NULL ELSE jsonb_build_object(
    'school', (SELECT jsonb_build_object(
                 'slug', slug, 'name', name, 'full_name', full_name,
                 'nickname', nickname, 'city', city, 'state', state,
                 'league', league_key, 'classification', classification,
                 'logo_url', logo_url, 'needs_review', auto_created) FROM sc),
    'today',    coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.starts_at)
                          FROM ev t WHERE t.event_date = t.today), '[]'::jsonb),
    'upcoming', coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.starts_at)
                          FROM ev t WHERE t.status = 'upcoming' AND t.event_date > t.today), '[]'::jsonb),
    'results',  coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.starts_at DESC)
                          FROM ev t WHERE t.status = 'final'), '[]'::jsonb))
  END;
$$;

GRANT EXECUTE ON FUNCTION public.gametracker_events(text,text,text,text,text,text,text,text,date,date,date,integer,text,integer,integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_event(uuid)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_filters(text, integer)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_school(text, integer)   TO anon, authenticated;
-- ============================================================================
-- 5-Star public "games around town" board.
-- PUBLIC (anon-readable) but exposes ONLY de-identified, team-level data for
-- GAMES + TOURNAMENTS (never practices). No child/family identifiers ever.
-- Same game appears on every teammate's calendar -> de-duplicated here.
-- A kill-switch table lets an admin hide any team instantly.
-- ============================================================================

-- kill switch: teams an admin has pulled from the public board
CREATE TABLE IF NOT EXISTS public.board_hidden_teams (
  team_name  text PRIMARY KEY,
  reason     text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.board_hidden_teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS board_hidden_service ON public.board_hidden_teams;
CREATE POLICY board_hidden_service ON public.board_hidden_teams
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- the public board function (SECURITY DEFINER: reads locked-down events, but
-- returns only safe, filtered, de-identified rows to the public)
CREATE OR REPLACE FUNCTION public.public_games_board(p_days int DEFAULT 7)
RETURNS TABLE (
  game_date   date,
  start_time  text,
  title       text,
  team        text,
  sport       text,
  venue       text,
  kind        text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  WITH base AS (
    SELECT
      (e."start" AT TIME ZONE 'America/New_York')::date AS game_date,
      to_char(e."start" AT TIME ZONE 'America/New_York', 'FMHH12:MI AM') AS start_time,
      trim(e.name)        AS title,
      trim(e.team_name)   AS team,
      e.sport,
      NULLIF(trim(e.location), '') AS venue,
      e."start"           AS starts_at,
      (e.name ~* '\m(practice|skills|training|workout|conditioning|open gym|camp|lesson|clinic|tryout)\M') AS is_practice,
      (e.name ~* '\m(tournament|showcase|invitational|classic|cup|championship|jamboree)\M') AS is_tournament,
      (e.name ~* '\mvs\M' OR e.name ~* ' @ ' OR e.name ~* '\mvs\.\M')                       AS is_game
    FROM public.events e
    WHERE coalesce(e.is_duplicate, false) = false
      AND e."start" IS NOT NULL
      AND e."start" >= now() - interval '4 hours'
      AND e."start" <= now() + make_interval(days => greatest(p_days, 1))
      AND trim(coalesce(e.team_name,'')) <> ''
      AND trim(e.team_name) NOT IN (SELECT team_name FROM public.board_hidden_teams)
  ),
  publishable AS (
    SELECT DISTINCT ON (lower(title), starts_at, lower(coalesce(venue,'')))
      game_date, start_time, title, team, sport, venue,
      CASE WHEN is_tournament THEN 'tournament' ELSE 'game' END AS kind
    FROM base
    WHERE is_practice = false        -- practices never published
      AND (is_game OR is_tournament)  -- only real games/tournaments
    ORDER BY lower(title), starts_at, lower(coalesce(venue,'')), team
  )
  SELECT game_date, start_time, title, team, sport, venue, kind
  FROM publishable
  ORDER BY game_date, start_time, title;
$$;

REVOKE ALL ON FUNCTION public.public_games_board(int) FROM public;
GRANT EXECUTE ON FUNCTION public.public_games_board(int) TO anon, authenticated;
CREATE SCHEMA IF NOT EXISTS gametracker;

REVOKE ALL ON SCHEMA gametracker FROM PUBLIC;
REVOKE ALL ON SCHEMA gametracker FROM anon, authenticated;

CREATE OR REPLACE FUNCTION gametracker.norm_text(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT nullif(
    trim(regexp_replace(
      regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', ' ', 'g'),
      '\s+', ' ', 'g')),
    '');
$$;

CREATE OR REPLACE FUNCTION gametracker.norm_school(p_name text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT gametracker.norm_text(
    regexp_replace(
      coalesce(p_name, ''),
      '(\m)(senior high school|junior senior high school|jr sr high school|high school|highschool|central school district|central school|senior high|sr high|jr/sr high|h\.s\.|hs|csd)(\M)',
      ' ', 'gi'));
$$;

CREATE OR REPLACE FUNCTION gametracker.slugify(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT replace(coalesce(gametracker.norm_text(p_text), ''), ' ', '-');
$$;

CREATE OR REPLACE FUNCTION gametracker.parse_time(p_raw text)
RETURNS time LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text := trim(coalesce(p_raw, ''));
BEGIN
  IF v = '' OR lower(v) IN ('tbd', 'tba', 'n/a', 'none') THEN RETURN NULL; END IF;
  v := regexp_replace(v, '\s+', ' ', 'g');
  v := regexp_replace(v, '^([0-9]{1,2}(:[0-9]{2})?)\s*([ap])\.?m\.?$', '\1 \3m', 'i');
  IF v ~ '^[0-9]{4}$' THEN v := left(v, 2) || ':' || right(v, 2); END IF;
  BEGIN
    RETURN v::time;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION gametracker.norm_status(p_raw text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE gametracker.norm_text(p_raw)
    WHEN 'upcoming'    THEN 'upcoming'
    WHEN 'scheduled'   THEN 'upcoming'
    WHEN 'pre'         THEN 'upcoming'
    WHEN 'pregame'     THEN 'upcoming'
    WHEN 'live'        THEN 'live'
    WHEN 'in progress' THEN 'live'
    WHEN 'inprogress'  THEN 'live'
    WHEN 'active'      THEN 'live'
    WHEN 'halftime'    THEN 'live'
    WHEN 'final'       THEN 'final'
    WHEN 'complete'    THEN 'final'
    WHEN 'completed'   THEN 'final'
    WHEN 'finished'    THEN 'final'
    WHEN 'postponed'   THEN 'postponed'
    WHEN 'ppd'         THEN 'postponed'
    WHEN 'delayed'     THEN 'postponed'
    WHEN 'cancelled'   THEN 'cancelled'
    WHEN 'canceled'    THEN 'cancelled'
    WHEN 'suspended'   THEN 'suspended'
    ELSE NULL
  END;
$$;

CREATE TABLE IF NOT EXISTS gametracker.sports (
  key                text PRIMARY KEY,
  display_name       text NOT NULL,
  base_sport         text NOT NULL,
  gender             text NOT NULL DEFAULT 'coed'
                       CHECK (gender IN ('boys', 'girls', 'coed', 'mixed')),
  season             text NOT NULL
                       CHECK (season IN ('fall', 'winter', 'spring', 'year-round')),
  scoring_model      text NOT NULL DEFAULT 'team_vs_team'
                       CHECK (scoring_model IN ('team_vs_team', 'meet', 'individual', 'bracket')),
  period_label       text NOT NULL DEFAULT 'Period',
  period_abbrev      text NOT NULL DEFAULT 'P',
  regulation_periods integer,
  has_clock          boolean NOT NULL DEFAULT true,
  sort_order         integer NOT NULL DEFAULT 100,
  active             boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS gametracker.leagues (
  key            text PRIMARY KEY,
  name           text NOT NULL,
  short_name     text,
  governing_body text,
  section        text,
  region         text DEFAULT 'WNY',
  level_of_play  text DEFAULT 'high-school',
  sort_order     integer NOT NULL DEFAULT 100,
  active         boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS gametracker.schools (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug           text NOT NULL UNIQUE,
  name           text NOT NULL,
  name_norm      text NOT NULL,
  full_name      text,
  nickname       text,
  city           text,
  state          text DEFAULT 'NY',
  county         text,
  league_key     text REFERENCES gametracker.leagues(key) ON DELETE SET NULL,
  classification text,
  logo_url       text,
  colors         jsonb,
  auto_created   boolean NOT NULL DEFAULT false,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS gt_schools_name_norm_idx ON gametracker.schools (name_norm);

CREATE TABLE IF NOT EXISTS gametracker.school_aliases (
  alias_norm text PRIMARY KEY,
  school_id  uuid NOT NULL REFERENCES gametracker.schools(id) ON DELETE CASCADE,
  source     text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gametracker.sources (
  key            text PRIMARY KEY,
  name           text NOT NULL,
  kind           text NOT NULL DEFAULT 'schedule'
                   CHECK (kind IN ('schedule', 'score', 'both', 'manual')),
  adapter        text NOT NULL DEFAULT 'json'
                   CHECK (adapter IN ('json', 'csv', 'arbiter', 'scorebird',
                                      'scorestream', 'scorescrape', 'manual', 'api')),
  publish        boolean NOT NULL DEFAULT false,
  trust_rank     integer NOT NULL DEFAULT 100,
  attribution    text,
  notes          text,
  last_import_at timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gametracker.events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source          text NOT NULL REFERENCES gametracker.sources(key) ON DELETE RESTRICT,
  source_event_id text NOT NULL,
  score_source    text REFERENCES gametracker.sources(key) ON DELETE SET NULL,
  sport           text NOT NULL REFERENCES gametracker.sports(key) ON DELETE RESTRICT,
  gender          text NOT NULL DEFAULT 'coed'
                    CHECK (gender IN ('boys', 'girls', 'coed', 'mixed')),
  level           text NOT NULL DEFAULT 'varsity',
  league          text REFERENCES gametracker.leagues(key) ON DELETE SET NULL,
  section         text,
  classification  text,
  season          integer NOT NULL,
  season_phase    text NOT NULL DEFAULT 'regular'
                    CHECK (season_phase IN ('preseason', 'scrimmage', 'regular',
                                            'tournament', 'playoff', 'championship')),
  region          text DEFAULT 'WNY',
  home_team_id    uuid REFERENCES gametracker.schools(id) ON DELETE SET NULL,
  away_team_id    uuid REFERENCES gametracker.schools(id) ON DELETE SET NULL,
  home_team_name  text NOT NULL,
  away_team_name  text,
  event_name      text,
  participants    jsonb NOT NULL DEFAULT '[]'::jsonb,
  event_date      date NOT NULL,
  start_time      time,
  timezone        text NOT NULL DEFAULT 'America/New_York',
  starts_at       timestamptz,
  venue           text,
  venue_detail    jsonb NOT NULL DEFAULT '{}'::jsonb,
  status          text NOT NULL DEFAULT 'upcoming'
                    CHECK (status IN ('upcoming', 'live', 'final',
                                      'postponed', 'cancelled', 'suspended')),
  home_score      integer,
  away_score      integer,
  period          text,
  clock           text,
  result_data     jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes           text,
  last_synced_at  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gt_events_source_uniq UNIQUE (source, source_event_id)
);

CREATE INDEX IF NOT EXISTS gt_events_date_idx    ON gametracker.events (event_date);
CREATE INDEX IF NOT EXISTS gt_events_starts_idx  ON gametracker.events (starts_at);
CREATE INDEX IF NOT EXISTS gt_events_sport_idx   ON gametracker.events (sport, event_date);
CREATE INDEX IF NOT EXISTS gt_events_league_idx  ON gametracker.events (league, event_date);
CREATE INDEX IF NOT EXISTS gt_events_status_idx  ON gametracker.events (status) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS gt_events_home_idx    ON gametracker.events (home_team_id, event_date);
CREATE INDEX IF NOT EXISTS gt_events_away_idx    ON gametracker.events (away_team_id, event_date);
CREATE INDEX IF NOT EXISTS gt_events_season_idx  ON gametracker.events (season, region);

CREATE TABLE IF NOT EXISTS gametracker.event_log (
  id           bigserial PRIMARY KEY,
  event_id     uuid REFERENCES gametracker.events(id) ON DELETE CASCADE,
  name         text NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);
CREATE INDEX IF NOT EXISTS gt_event_log_undelivered_idx
  ON gametracker.event_log (occurred_at) WHERE delivered_at IS NULL;

CREATE TABLE IF NOT EXISTS gametracker.import_batches (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source          text,
  adapter         text,
  dry_run         boolean NOT NULL DEFAULT true,
  submitted_by    uuid,
  total_count     integer NOT NULL DEFAULT 0,
  created_count   integer NOT NULL DEFAULT 0,
  updated_count   integer NOT NULL DEFAULT 0,
  unchanged_count integer NOT NULL DEFAULT 0,
  failed_count    integer NOT NULL DEFAULT 0,
  result          jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at      timestamptz NOT NULL DEFAULT now(),
  finished_at     timestamptz
);

ALTER TABLE gametracker.sports         ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.leagues        ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.schools        ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.school_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.sources        ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.event_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE gametracker.import_batches ENABLE ROW LEVEL SECURITY;
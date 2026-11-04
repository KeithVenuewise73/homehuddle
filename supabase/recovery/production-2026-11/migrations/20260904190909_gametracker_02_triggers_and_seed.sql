CREATE OR REPLACE FUNCTION gametracker.tg_events_derive()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.starts_at := (NEW.event_date + coalesce(NEW.start_time, time '00:00'))
                     AT TIME ZONE coalesce(NEW.timezone, 'America/New_York');
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS gt_events_derive ON gametracker.events;
CREATE TRIGGER gt_events_derive
  BEFORE INSERT OR UPDATE ON gametracker.events
  FOR EACH ROW EXECUTE FUNCTION gametracker.tg_events_derive();

CREATE OR REPLACE FUNCTION gametracker.tg_events_emit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_base jsonb;
BEGIN
  v_base := jsonb_build_object(
    'event_id',   NEW.id,
    'sport',      NEW.sport,
    'league',     NEW.league,
    'region',     NEW.region,
    'home_team',  NEW.home_team_name,
    'away_team',  NEW.away_team_name,
    'event_date', NEW.event_date,
    'status',     NEW.status,
    'home_score', NEW.home_score,
    'away_score', NEW.away_score,
    'source',     NEW.source);

  IF TG_OP = 'INSERT' THEN
    INSERT INTO gametracker.event_log (event_id, name, payload)
    VALUES (NEW.id, 'game.created', v_base);
    IF NEW.status = 'live'  THEN
      INSERT INTO gametracker.event_log (event_id, name, payload)
      VALUES (NEW.id, 'game.started', v_base);
    ELSIF NEW.status = 'final' THEN
      INSERT INTO gametracker.event_log (event_id, name, payload)
      VALUES (NEW.id, 'game.final', v_base);
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO gametracker.event_log (event_id, name, payload)
    VALUES (NEW.id,
      CASE NEW.status
        WHEN 'live'      THEN 'game.started'
        WHEN 'final'     THEN 'game.final'
        WHEN 'cancelled' THEN 'game.cancelled'
        WHEN 'postponed' THEN 'game.postponed'
        ELSE 'game.updated'
      END,
      v_base || jsonb_build_object('previous_status', OLD.status));
  END IF;

  IF NEW.home_score IS DISTINCT FROM OLD.home_score
     OR NEW.away_score IS DISTINCT FROM OLD.away_score THEN
    INSERT INTO gametracker.event_log (event_id, name, payload)
    VALUES (NEW.id, 'score.updated',
      v_base || jsonb_build_object(
        'previous_home_score', OLD.home_score,
        'previous_away_score', OLD.away_score,
        'period', NEW.period,
        'clock',  NEW.clock));
  END IF;

  IF NEW.event_date IS DISTINCT FROM OLD.event_date
     OR NEW.start_time IS DISTINCT FROM OLD.start_time
     OR NEW.venue IS DISTINCT FROM OLD.venue THEN
    INSERT INTO gametracker.event_log (event_id, name, payload)
    VALUES (NEW.id, 'game.updated',
      v_base || jsonb_build_object(
        'previous_event_date', OLD.event_date,
        'previous_start_time', OLD.start_time,
        'previous_venue',      OLD.venue,
        'venue',               NEW.venue));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS gt_events_emit ON gametracker.events;
CREATE TRIGGER gt_events_emit
  AFTER INSERT OR UPDATE ON gametracker.events
  FOR EACH ROW EXECUTE FUNCTION gametracker.tg_events_emit();

CREATE OR REPLACE FUNCTION gametracker.tg_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS gt_schools_touch ON gametracker.schools;
CREATE TRIGGER gt_schools_touch BEFORE UPDATE ON gametracker.schools
  FOR EACH ROW EXECUTE FUNCTION gametracker.tg_touch();

DROP TRIGGER IF EXISTS gt_sources_touch ON gametracker.sources;
CREATE TRIGGER gt_sources_touch BEFORE UPDATE ON gametracker.sources
  FOR EACH ROW EXECUTE FUNCTION gametracker.tg_touch();

INSERT INTO gametracker.sports
  (key, display_name, base_sport, gender, season, scoring_model, period_label, period_abbrev, regulation_periods, has_clock, sort_order)
VALUES
  ('football',              'Football',                'football',     'boys',  'fall',   'team_vs_team', 'Quarter', 'Q',    4, true,  10),
  ('boys-soccer',           'Boys Soccer',             'soccer',       'boys',  'fall',   'team_vs_team', 'Half',    'H',    2, true,  20),
  ('girls-soccer',          'Girls Soccer',            'soccer',       'girls', 'fall',   'team_vs_team', 'Half',    'H',    2, true,  21),
  ('girls-volleyball',      'Girls Volleyball',        'volleyball',   'girls', 'fall',   'team_vs_team', 'Set',     'Set',  5, false, 30),
  ('boys-volleyball',       'Boys Volleyball',         'volleyball',   'boys',  'fall',   'team_vs_team', 'Set',     'Set',  5, false, 31),
  ('field-hockey',          'Field Hockey',            'field-hockey', 'girls', 'fall',   'team_vs_team', 'Quarter', 'Q',    4, true,  40),
  ('boys-cross-country',    'Boys Cross Country',      'cross-country','boys',  'fall',   'meet',         'Race',    'Race', NULL, false, 50),
  ('girls-cross-country',   'Girls Cross Country',     'cross-country','girls', 'fall',   'meet',         'Race',    'Race', NULL, false, 51),
  ('girls-swimming',        'Girls Swimming & Diving', 'swimming',     'girls', 'fall',   'meet',         'Event',   'Ev',   NULL, false, 60),
  ('girls-tennis',          'Girls Tennis',            'tennis',       'girls', 'fall',   'individual',   'Match',   'M',    NULL, false, 70),
  ('girls-golf',            'Girls Golf',              'golf',         'girls', 'fall',   'meet',         'Round',   'Rd',   NULL, false, 80),
  ('boys-golf-fall',        'Boys Golf (Fall)',        'golf',         'boys',  'fall',   'meet',         'Round',   'Rd',   NULL, false, 81),
  ('girls-gymnastics',      'Girls Gymnastics',        'gymnastics',   'girls', 'fall',   'meet',         'Rotation','Rot',  NULL, false, 90),
  ('boys-cheer-fall',       'Competitive Cheer (Fall)','cheer',        'coed',  'fall',   'meet',         'Round',   'Rd',   NULL, false, 95),
  ('boys-basketball',       'Boys Basketball',         'basketball',   'boys',  'winter', 'team_vs_team', 'Quarter', 'Q',    4, true, 110),
  ('girls-basketball',      'Girls Basketball',        'basketball',   'girls', 'winter', 'team_vs_team', 'Quarter', 'Q',    4, true, 111),
  ('boys-ice-hockey',       'Boys Ice Hockey',         'ice-hockey',   'boys',  'winter', 'team_vs_team', 'Period',  'P',    3, true, 120),
  ('girls-ice-hockey',      'Girls Ice Hockey',        'ice-hockey',   'girls', 'winter', 'team_vs_team', 'Period',  'P',    3, true, 121),
  ('wrestling',             'Wrestling',               'wrestling',    'boys',  'winter', 'team_vs_team', 'Bout',    'Bout', NULL, false, 130),
  ('girls-wrestling',       'Girls Wrestling',         'wrestling',    'girls', 'winter', 'team_vs_team', 'Bout',    'Bout', NULL, false, 131),
  ('boys-swimming',         'Boys Swimming & Diving',  'swimming',     'boys',  'winter', 'meet',         'Event',   'Ev',   NULL, false, 140),
  ('boys-indoor-track',     'Boys Indoor Track & Field','indoor-track','boys',  'winter', 'meet',         'Event',   'Ev',   NULL, false, 150),
  ('girls-indoor-track',    'Girls Indoor Track & Field','indoor-track','girls','winter', 'meet',         'Event',   'Ev',   NULL, false, 151),
  ('boys-bowling',          'Boys Bowling',            'bowling',      'boys',  'winter', 'team_vs_team', 'Game',    'G',    3, false, 160),
  ('girls-bowling',         'Girls Bowling',           'bowling',      'girls', 'winter', 'team_vs_team', 'Game',    'G',    3, false, 161),
  ('competitive-cheer',     'Competitive Cheer',       'cheer',        'coed',  'winter', 'meet',         'Round',   'Rd',   NULL, false, 170),
  ('unified-basketball',    'Unified Basketball',      'basketball',   'coed',  'winter', 'team_vs_team', 'Quarter', 'Q',    4, true, 180),
  ('boys-skiing',           'Boys Alpine Skiing',      'skiing',       'boys',  'winter', 'meet',         'Run',     'Run',  NULL, false, 190),
  ('girls-skiing',          'Girls Alpine Skiing',     'skiing',       'girls', 'winter', 'meet',         'Run',     'Run',  NULL, false, 191),
  ('baseball',              'Baseball',                'baseball',     'boys',  'spring', 'team_vs_team', 'Inning',  'Inn',  7, false, 210),
  ('softball',              'Softball',                'softball',     'girls', 'spring', 'team_vs_team', 'Inning',  'Inn',  7, false, 211),
  ('boys-lacrosse',         'Boys Lacrosse',           'lacrosse',     'boys',  'spring', 'team_vs_team', 'Quarter', 'Q',    4, true, 220),
  ('girls-lacrosse',        'Girls Lacrosse',          'lacrosse',     'girls', 'spring', 'team_vs_team', 'Half',    'H',    2, true, 221),
  ('boys-track',            'Boys Track & Field',      'track',        'boys',  'spring', 'meet',         'Event',   'Ev',   NULL, false, 230),
  ('girls-track',           'Girls Track & Field',     'track',        'girls', 'spring', 'meet',         'Event',   'Ev',   NULL, false, 231),
  ('boys-tennis',           'Boys Tennis',             'tennis',       'boys',  'spring', 'individual',   'Match',   'M',    NULL, false, 240),
  ('boys-golf',             'Boys Golf',               'golf',         'boys',  'spring', 'meet',         'Round',   'Rd',   NULL, false, 250),
  ('boys-crew',             'Boys Crew',               'crew',         'boys',  'spring', 'meet',         'Race',    'Race', NULL, false, 260),
  ('girls-crew',            'Girls Crew',              'crew',         'girls', 'spring', 'meet',         'Race',    'Race', NULL, false, 261),
  ('girls-flag-football',   'Girls Flag Football',     'flag-football','girls', 'spring', 'team_vs_team', 'Half',    'H',    2, true, 270)
ON CONFLICT (key) DO UPDATE SET
  display_name       = EXCLUDED.display_name,
  base_sport         = EXCLUDED.base_sport,
  gender             = EXCLUDED.gender,
  season             = EXCLUDED.season,
  scoring_model      = EXCLUDED.scoring_model,
  period_label       = EXCLUDED.period_label,
  period_abbrev      = EXCLUDED.period_abbrev,
  regulation_periods = EXCLUDED.regulation_periods,
  has_clock          = EXCLUDED.has_clock,
  sort_order         = EXCLUDED.sort_order;

INSERT INTO gametracker.leagues (key, name, short_name, governing_body, section, region, sort_order)
VALUES
  ('section-vi',       'Section VI',                'Section VI', 'NYSPHSAA', 'VI', 'WNY', 10),
  ('monsignor-martin', 'Monsignor Martin',          'MMHSAA',     'MMHSAA',   NULL, 'WNY', 20),
  ('section-v',        'Section V',                 'Section V',  'NYSPHSAA', 'V',  'WNY', 30),
  ('independent',      'Independent / Non-League',  'Ind.',        NULL,      NULL, 'WNY', 90)
ON CONFLICT (key) DO UPDATE SET
  name = EXCLUDED.name, short_name = EXCLUDED.short_name,
  governing_body = EXCLUDED.governing_body, section = EXCLUDED.section,
  region = EXCLUDED.region, sort_order = EXCLUDED.sort_order;

INSERT INTO gametracker.sources (key, name, kind, adapter, publish, trust_rank, notes)
VALUES
  ('manual_admin', 'Manual admin entry', 'both', 'manual', true,  10,
   'Corrections and hand-entered events made by an authorized 5-Star admin. Highest trust.'),
  ('selftest',     'Pipeline self-test', 'both', 'json',   false, 900,
   'Never published. Used to verify import/upsert/status transitions against the live database.')
ON CONFLICT (key) DO UPDATE SET
  name = EXCLUDED.name, kind = EXCLUDED.kind, adapter = EXCLUDED.adapter,
  trust_rank = EXCLUDED.trust_rank, notes = EXCLUDED.notes;
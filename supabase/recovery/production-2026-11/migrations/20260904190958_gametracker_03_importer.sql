CREATE OR REPLACE FUNCTION gametracker.resolve_school(
  p_name   text,
  p_league text DEFAULT NULL,
  p_create boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
DECLARE
  v_norm text := gametracker.norm_school(p_name);
  v_id   uuid;
  v_slug text;
  v_n    integer := 1;
BEGIN
  IF v_norm IS NULL THEN RETURN NULL; END IF;

  SELECT school_id INTO v_id FROM gametracker.school_aliases WHERE alias_norm = v_norm;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  SELECT id INTO v_id FROM gametracker.schools WHERE name_norm = v_norm;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  IF NOT p_create THEN RETURN NULL; END IF;

  v_slug := gametracker.slugify(v_norm);
  WHILE EXISTS (SELECT 1 FROM gametracker.schools WHERE slug = v_slug) LOOP
    v_n := v_n + 1;
    v_slug := gametracker.slugify(v_norm) || '-' || v_n;
  END LOOP;

  INSERT INTO gametracker.schools (slug, name, name_norm, league_key, auto_created)
  VALUES (v_slug, trim(p_name), v_norm, p_league, true)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION gametracker.import_events(
  p_payload        jsonb,
  p_dry_run        boolean DEFAULT true,
  p_default_source text    DEFAULT NULL,
  p_submitted_by   uuid    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'gametracker', 'public', 'pg_temp'
AS $$
DECLARE
  v_items       jsonb;
  v_item        jsonb;
  v_idx         integer := 0;
  v_batch       uuid := gen_random_uuid();
  v_rows        jsonb := '[]'::jsonb;
  v_created     integer := 0;
  v_updated     integer := 0;
  v_unchanged   integer := 0;
  v_failed      integer := 0;
  v_sources     text[] := '{}';
  v_source      text;
  v_sid         text;
  v_sport       text;
  v_status      text;
  v_date        date;
  v_time        time;
  v_season      integer;
  v_home        text;
  v_away        text;
  v_league      text;
  v_gender      text;
  v_level       text;
  v_tz          text;
  v_home_id     uuid;
  v_away_id     uuid;
  v_existing    gametracker.events%ROWTYPE;
  v_changes     text[];
  v_err         text;
  v_action      text;
  v_label       text;
  v_id          uuid;
BEGIN
  v_items := CASE
    WHEN jsonb_typeof(p_payload) = 'array' THEN p_payload
    WHEN p_payload ? 'events' THEN p_payload -> 'events'
    WHEN p_payload ? 'games'  THEN p_payload -> 'games'
    ELSE NULL
  END;

  IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Payload must be a JSON array of events, or an object with an "events" or "games" array.');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    v_idx     := v_idx + 1;
    v_err     := NULL;
    v_changes := '{}';
    v_action  := NULL;
    v_id      := NULL;
    v_label   := NULL;

    BEGIN
      v_source := nullif(trim(coalesce(v_item ->> 'source', p_default_source, '')), '');
      v_sid    := nullif(trim(coalesce(v_item ->> 'source_event_id',
                                       v_item ->> 'source_game_id', '')), '');
      v_sport  := nullif(gametracker.slugify(coalesce(v_item ->> 'sport', '')), '');
      v_home   := nullif(trim(coalesce(v_item ->> 'home_team_name',
                                       v_item ->> 'home_team', '')), '');
      v_away   := nullif(trim(coalesce(v_item ->> 'away_team_name',
                                       v_item ->> 'away_team', '')), '');
      v_tz     := coalesce(nullif(trim(coalesce(v_item ->> 'timezone', '')), ''), 'America/New_York');

      IF v_source IS NULL THEN
        RAISE EXCEPTION 'missing "source" (and no default source supplied)';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM gametracker.sources WHERE key = v_source) THEN
        RAISE EXCEPTION 'unknown source "%" - register it in gametracker.sources first', v_source;
      END IF;
      IF v_sid IS NULL THEN
        RAISE EXCEPTION 'missing "source_event_id"';
      END IF;
      IF v_sport IS NULL OR NOT EXISTS (SELECT 1 FROM gametracker.sports WHERE key = v_sport) THEN
        RAISE EXCEPTION 'unknown sport "%" - must be a key in gametracker.sports', coalesce(v_item ->> 'sport', '');
      END IF;
      IF v_home IS NULL THEN
        RAISE EXCEPTION 'missing "home_team_name"';
      END IF;

      BEGIN
        v_date := (coalesce(v_item ->> 'event_date', v_item ->> 'game_date', v_item ->> 'date'))::date;
      EXCEPTION WHEN others THEN
        RAISE EXCEPTION 'unparseable date "%" - use YYYY-MM-DD',
          coalesce(v_item ->> 'event_date', v_item ->> 'game_date', v_item ->> 'date', '');
      END;
      IF v_date IS NULL THEN RAISE EXCEPTION 'missing "event_date"'; END IF;

      v_time := gametracker.parse_time(coalesce(v_item ->> 'start_time', v_item ->> 'time'));

      v_status := coalesce(gametracker.norm_status(v_item ->> 'status'), 'upcoming');

      v_season := coalesce(
        nullif(regexp_replace(coalesce(v_item ->> 'season', ''), '[^0-9]', '', 'g'), '')::integer,
        CASE WHEN extract(month FROM v_date) >= 7
             THEN extract(year FROM v_date)::integer
             ELSE extract(year FROM v_date)::integer - 1 END);

      v_league := nullif(gametracker.slugify(coalesce(v_item ->> 'league', '')), '');
      IF v_league IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gametracker.leagues WHERE key = v_league) THEN
        RAISE EXCEPTION 'unknown league "%" - register it in gametracker.leagues first', v_item ->> 'league';
      END IF;

      v_gender := coalesce(nullif(lower(trim(coalesce(v_item ->> 'gender', ''))), ''),
                           (SELECT gender FROM gametracker.sports WHERE key = v_sport));
      v_level  := coalesce(nullif(lower(trim(coalesce(v_item ->> 'level', ''))), ''), 'varsity');

      v_home_id := gametracker.resolve_school(v_home, v_league, NOT p_dry_run);
      v_away_id := gametracker.resolve_school(v_away, v_league, NOT p_dry_run);

      v_label := coalesce(v_away, 'TBD') || ' @ ' || v_home;

      SELECT * INTO v_existing
      FROM gametracker.events
      WHERE source = v_source AND source_event_id = v_sid;

      IF v_existing.id IS NULL THEN
        v_action := 'create';
      ELSE
        v_id := v_existing.id;
        IF v_existing.event_date  IS DISTINCT FROM v_date  THEN v_changes := v_changes || 'event_date'; END IF;
        IF v_existing.start_time  IS DISTINCT FROM v_time  THEN v_changes := v_changes || 'start_time'; END IF;
        IF v_existing.venue       IS DISTINCT FROM nullif(trim(coalesce(v_item ->> 'venue','')),'')
                                                            THEN v_changes := v_changes || 'venue'; END IF;
        IF v_existing.status      IS DISTINCT FROM v_status THEN v_changes := v_changes || 'status'; END IF;
        IF v_existing.home_team_name IS DISTINCT FROM v_home THEN v_changes := v_changes || 'home_team_name'; END IF;
        IF v_existing.away_team_name IS DISTINCT FROM v_away THEN v_changes := v_changes || 'away_team_name'; END IF;
        IF v_existing.sport       IS DISTINCT FROM v_sport  THEN v_changes := v_changes || 'sport'; END IF;
        IF v_existing.league      IS DISTINCT FROM v_league THEN v_changes := v_changes || 'league'; END IF;
        IF v_existing.level       IS DISTINCT FROM v_level  THEN v_changes := v_changes || 'level'; END IF;
        v_action := CASE WHEN cardinality(v_changes) > 0 THEN 'update' ELSE 'unchanged' END;
      END IF;

      IF NOT p_dry_run THEN
        INSERT INTO gametracker.events AS e (
          source, source_event_id, sport, gender, level, league, section,
          classification, season, season_phase, region,
          home_team_id, away_team_id, home_team_name, away_team_name,
          event_name, participants, event_date, start_time, timezone, venue,
          status, notes, last_synced_at)
        VALUES (
          v_source, v_sid, v_sport, v_gender, v_level, v_league,
          nullif(trim(coalesce(v_item ->> 'section', '')), ''),
          nullif(trim(coalesce(v_item ->> 'classification', '')), ''),
          v_season,
          coalesce(nullif(lower(trim(coalesce(v_item ->> 'season_phase', ''))), ''), 'regular'),
          coalesce(nullif(trim(coalesce(v_item ->> 'region', '')), ''), 'WNY'),
          v_home_id, v_away_id, v_home, v_away,
          nullif(trim(coalesce(v_item ->> 'event_name', '')), ''),
          coalesce(v_item -> 'participants', '[]'::jsonb),
          v_date, v_time, v_tz,
          nullif(trim(coalesce(v_item ->> 'venue', '')), ''),
          v_status,
          nullif(trim(coalesce(v_item ->> 'notes', '')), ''),
          now())
        ON CONFLICT (source, source_event_id) DO UPDATE SET
          sport          = EXCLUDED.sport,
          gender         = EXCLUDED.gender,
          level          = EXCLUDED.level,
          league         = EXCLUDED.league,
          section        = EXCLUDED.section,
          classification = EXCLUDED.classification,
          season         = EXCLUDED.season,
          season_phase   = EXCLUDED.season_phase,
          region         = EXCLUDED.region,
          home_team_id   = coalesce(EXCLUDED.home_team_id, e.home_team_id),
          away_team_id   = coalesce(EXCLUDED.away_team_id, e.away_team_id),
          home_team_name = EXCLUDED.home_team_name,
          away_team_name = EXCLUDED.away_team_name,
          event_name     = EXCLUDED.event_name,
          participants   = EXCLUDED.participants,
          event_date     = EXCLUDED.event_date,
          start_time     = EXCLUDED.start_time,
          timezone       = EXCLUDED.timezone,
          venue          = EXCLUDED.venue,
          status         = CASE
                             WHEN e.status IN ('live', 'final')
                                  AND EXCLUDED.status = 'upcoming' THEN e.status
                             ELSE EXCLUDED.status
                           END,
          notes          = EXCLUDED.notes,
          last_synced_at = now()
        RETURNING e.id INTO v_id;
      END IF;

      CASE v_action
        WHEN 'create'    THEN v_created   := v_created + 1;
        WHEN 'update'    THEN v_updated   := v_updated + 1;
        ELSE                  v_unchanged := v_unchanged + 1;
      END CASE;

      IF NOT (v_source = ANY (v_sources)) THEN v_sources := v_sources || v_source; END IF;

      v_rows := v_rows || jsonb_build_object(
        'index',           v_idx,
        'source',          v_source,
        'source_event_id', v_sid,
        'matchup',         v_label,
        'sport',           v_sport,
        'event_date',      v_date,
        'start_time',      v_time,
        'status',          v_status,
        'action',          v_action,
        'changes',         to_jsonb(v_changes),
        'event_id',        v_id);

    EXCEPTION WHEN others THEN
      v_failed := v_failed + 1;
      v_err := SQLERRM;
      v_rows := v_rows || jsonb_build_object(
        'index',           v_idx,
        'source',          v_source,
        'source_event_id', v_sid,
        'matchup',         coalesce(v_label, ''),
        'action',          'error',
        'error',           v_err);
    END;
  END LOOP;

  IF NOT p_dry_run AND array_length(v_sources, 1) > 0 THEN
    UPDATE gametracker.sources SET last_import_at = now() WHERE key = ANY (v_sources);
  END IF;

  INSERT INTO gametracker.import_batches (
    id, source, dry_run, submitted_by, total_count,
    created_count, updated_count, unchanged_count, failed_count, result, finished_at)
  VALUES (
    v_batch,
    coalesce(array_to_string(v_sources, ','), p_default_source),
    p_dry_run, p_submitted_by, v_idx,
    v_created, v_updated, v_unchanged, v_failed,
    jsonb_build_object('rows', v_rows), now());

  RETURN jsonb_build_object(
    'ok',       v_failed = 0,
    'dry_run',  p_dry_run,
    'batch_id', v_batch,
    'sources',  to_jsonb(v_sources),
    'summary',  jsonb_build_object(
                  'total',     v_idx,
                  'created',   v_created,
                  'updated',   v_updated,
                  'unchanged', v_unchanged,
                  'failed',    v_failed),
    'message',  CASE
                  WHEN v_idx = 0 THEN 'Nothing to import - the file contained no events.'
                  WHEN p_dry_run THEN
                    format('Preview only, nothing saved. %s to add, %s to update, %s already current, %s with problems.',
                           v_created, v_updated, v_unchanged, v_failed)
                  ELSE
                    format('Imported. %s added, %s updated, %s already current, %s with problems.',
                           v_created, v_updated, v_unchanged, v_failed)
                END,
    'rows',     v_rows);
END;
$$;

REVOKE ALL ON FUNCTION gametracker.import_events(jsonb, boolean, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION gametracker.resolve_school(text, text, boolean)       FROM PUBLIC, anon, authenticated;
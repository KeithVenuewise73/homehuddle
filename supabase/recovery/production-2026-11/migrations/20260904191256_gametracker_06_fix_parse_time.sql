-- Real schedule files write start times a dozen ways. The first cut handled
-- '18:00', '6:00 PM' and '1800' but silently dropped '630pm' -- and a silently
-- missing start time is exactly the kind of quiet wrong answer a scoreboard
-- must not produce. Parse the meridiem first, then the digits.
CREATE OR REPLACE FUNCTION gametracker.parse_time(p_raw text)
RETURNS time LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v    text := lower(trim(coalesce(p_raw, '')));
  v_pm boolean := NULL;
  v_h  integer;
  v_m  integer := 0;
BEGIN
  IF v = '' OR v IN ('tbd', 'tba', 'n/a', 'na', 'none', '-') THEN RETURN NULL; END IF;

  -- meridiem, however it is punctuated: 'pm', 'p.m.', 'P M'
  IF v ~ '[ap]\.?\s?m\.?$' THEN
    v_pm := (regexp_replace(v, '^.*([ap])\.?\s?m\.?$', '\1') = 'p');
    v := trim(regexp_replace(v, '[ap]\.?\s?m\.?$', ''));
  END IF;

  v := regexp_replace(v, '[\s.]', '', 'g');   -- '6.30' / '6 30' -> '630'

  IF    v ~ '^[0-9]{1,2}$'            THEN v_h := v::integer;
  ELSIF v ~ '^[0-9]{1,2}:[0-9]{2}$'   THEN v_h := split_part(v, ':', 1)::integer;
                                           v_m := split_part(v, ':', 2)::integer;
  ELSIF v ~ '^[0-9]{3}$'              THEN v_h := left(v, 1)::integer;
                                           v_m := right(v, 2)::integer;
  ELSIF v ~ '^[0-9]{4}$'              THEN v_h := left(v, 2)::integer;
                                           v_m := right(v, 2)::integer;
  ELSIF v ~ '^[0-9]{1,2}:[0-9]{2}:[0-9]{2}$' THEN
                                           v_h := split_part(v, ':', 1)::integer;
                                           v_m := split_part(v, ':', 2)::integer;
  ELSE  RETURN NULL;                        -- unrecognized: say nothing, never guess
  END IF;

  IF v_pm IS TRUE  AND v_h < 12 THEN v_h := v_h + 12; END IF;
  IF v_pm IS FALSE AND v_h = 12 THEN v_h := 0;        END IF;

  IF v_h > 23 OR v_m > 59 THEN RETURN NULL; END IF;
  RETURN make_time(v_h, v_m, 0);
END;
$$;
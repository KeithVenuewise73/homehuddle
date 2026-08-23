-- ============================================================================
-- PlayingTime schema verification.
--
-- Structure, constraints, derived participation, and — the part that matters —
-- that one parent cannot read or write another parent's athlete. Each check
-- raises an exception on failure, so a non-zero psql exit means a real failure.
-- ============================================================================
\set ON_ERROR_STOP on

create or replace function pt_assert(label text, condition boolean) returns void
language plpgsql as $$
begin
  if condition then
    raise notice '  ok   %', label;
  else
    raise exception 'FAILED: %', label;
  end if;
end $$;

-- ---------------------------------------------------------------- structure --
do $$
declare n int;
begin
  raise notice '# Structure';
  perform pt_assert('playingtime schema exists',
    exists (select 1 from pg_namespace where nspname = 'playingtime'));

  select count(*) into n from pg_tables where schemaname = 'playingtime';
  perform pt_assert('9 tables created (units, stat_types, profiles, athletes, seasons, games, plays, stats, score_events)', n = 9);

  perform pt_assert('game_units is a view, not a stored total (§26)',
    exists (select 1 from pg_views where schemaname = 'playingtime' and viewname = 'game_units'));

  select count(*) into n from playingtime.stat_types;
  perform pt_assert('31 stat types seeded across the three units', n = 31);

  select count(*) into n from playingtime.stat_types where unit = 'defense';
  perform pt_assert('10 defensive stat types (§9)', n = 10);

  select count(*) into n from playingtime.stat_types where has_yardage;
  perform pt_assert('5 stat types open the yardage sheet (§12)', n = 5);
end $$;

-- ---------------------------------------------------------------------- RLS --
do $$
declare t text; n int;
begin
  raise notice '# Row Level Security';
  foreach t in array array['profiles','athletes','seasons','games','plays','stats','score_events'] loop
    perform pt_assert(format('%s has RLS enabled AND forced', t), exists (
      select 1 from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
      where ns.nspname = 'playingtime' and c.relname = t
        and c.relrowsecurity and c.relforcerowsecurity));
  end loop;

  select count(*) into n
    from pg_policies where schemaname = 'playingtime' and 'anon' = any(roles);
  perform pt_assert('no policy grants anything to anonymous visitors', n = 0);

  select count(*) into n
    from pg_policies
   where schemaname = 'playingtime'
     and tablename in ('profiles','athletes','seasons','games','plays','stats','score_events')
     and qual = 'true';
  perform pt_assert('no owned table is readable by any signed-in user', n = 0);
end $$;

-- ------------------------------------------------------------- derived math --
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  ath uuid; gm uuid; i int;
  team int; plays int; part numeric;
begin
  raise notice '# Derived participation';
  insert into auth.users (id, email) values (alice, 'alice@example.com');
  insert into playingtime.profiles (id, email, name) values (alice, 'alice@example.com', 'Alice');
  insert into playingtime.athletes (user_id, name, primary_position)
    values (alice, 'Dominic Herman', 'LB') returning id into ath;
  insert into playingtime.games (athlete_id, opponent, game_date)
    values (ath, 'Lancaster', date '2026-09-11') returning id into gm;

  for i in 1..51 loop
    insert into playingtime.plays (game_id, seq, quarter, unit, athlete_in)
      values (gm, i, 'Q1', 'defense', i <= 37);
  end loop;
  for i in 52..63 loop
    insert into playingtime.plays (game_id, seq, quarter, unit, athlete_in)
      values (gm, i, 'Q2', 'special_teams', i <= 59);
  end loop;

  select team_plays, athlete_plays, participation into team, plays, part
    from playingtime.game_units where game_id = gm and unit = 'defense';
  perform pt_assert('defense: 37 of 51 plays', team = 51 and plays = 37);
  perform pt_assert('defense participation is 72.5% (brief §17)', part = 72.5);

  select team_plays, athlete_plays, participation into team, plays, part
    from playingtime.game_units where game_id = gm and unit = 'special_teams';
  perform pt_assert('special teams: 8 of 12 plays at 66.7%', team = 12 and plays = 8 and part = 66.7);

  insert into playingtime.stats (game_id, athlete_id, seq, stat_type, quarter, unit, yards)
    values (gm, ath, 1, 'rush_att', 'Q1', 'offense', 5),
           (gm, ath, 2, 'rush_att', 'Q1', 'offense', null);
  perform pt_assert('missing yardage stays null, never coerced to zero',
    (select count(*) from playingtime.stats where game_id = gm and yards is null) = 1);
end $$;

-- ------------------------------------------------------------- constraints --
do $$
declare ath uuid; gm uuid;
begin
  raise notice '# Constraints';
  select id into ath from playingtime.athletes limit 1;
  select id into gm  from playingtime.games limit 1;

  begin
    insert into playingtime.plays (game_id, seq, quarter, unit, athlete_in)
      values (gm, 900, 'Q5', 'defense', true);
    raise exception 'FAILED: a fifth quarter was accepted';
  exception when check_violation then
    perform pt_assert('an invalid quarter is rejected', true);
  end;

  begin
    insert into playingtime.plays (game_id, seq, quarter, unit, athlete_in)
      values (gm, 901, 'Q1', 'punt_team', true);
    raise exception 'FAILED: an unknown unit was accepted';
  exception when foreign_key_violation then
    perform pt_assert('an unknown unit is rejected', true);
  end;

  begin
    insert into playingtime.stats (game_id, athlete_id, seq, stat_type, quarter, unit)
      values (gm, ath, 900, 'hurdle', 'Q1', 'defense');
    raise exception 'FAILED: an unknown stat type was accepted';
  exception when foreign_key_violation then
    perform pt_assert('an unknown stat type is rejected', true);
  end;

  begin
    insert into playingtime.athletes (user_id, name)
      values ((select id from playingtime.profiles limit 1), '   ');
    raise exception 'FAILED: a blank athlete name was accepted';
  exception when check_violation then
    perform pt_assert('a blank athlete name is rejected', true);
  end;
end $$;

-- -------------------------------------------------- one parent, one athlete --
-- The real test: RLS enforced as the `authenticated` role, the way the app runs.
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  bob_ath uuid; bob_gm uuid; n int;
begin
  raise notice '# Isolation between two parents';
  insert into auth.users (id, email) values (bob, 'bob@example.com');
  insert into playingtime.profiles (id, email, name) values (bob, 'bob@example.com', 'Bob');
  insert into playingtime.athletes (user_id, name, primary_position)
    values (bob, 'Other Kid', 'WR') returning id into bob_ath;
  insert into playingtime.games (athlete_id, opponent, game_date)
    values (bob_ath, 'Clarence', date '2026-09-18') returning id into bob_gm;
  insert into playingtime.plays (game_id, seq, quarter, unit, athlete_in)
    values (bob_gm, 1, 'Q1', 'offense', true);

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', alice::text, true);

  select count(*) into n from playingtime.athletes;
  perform pt_assert('Alice sees only her own athlete', n = 1);
  perform pt_assert('Alice cannot see Bob''s athlete',
    not exists (select 1 from playingtime.athletes where id = bob_ath));

  select count(*) into n from playingtime.games;
  perform pt_assert('Alice sees only her own games', n = 1);

  select count(*) into n from playingtime.plays where game_id = bob_gm;
  perform pt_assert('Alice cannot read plays from Bob''s game', n = 0);

  select count(*) into n from playingtime.game_units where game_id = bob_gm;
  perform pt_assert('the derived view leaks nothing either', n = 0);

  begin
    insert into playingtime.games (athlete_id, opponent, game_date)
      values (bob_ath, 'Injected', date '2026-10-01');
    raise exception 'FAILED: Alice created a game against Bob''s athlete';
  exception when insufficient_privilege then
    perform pt_assert('Alice cannot create a game for Bob''s athlete', true);
  end;

  begin
    update playingtime.athletes set name = 'Renamed' where id = bob_ath;
    perform pt_assert('Alice''s update to Bob''s athlete affected no rows', not found);
  end;

  reset role;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*) into n from playingtime.athletes;
  perform pt_assert('both athletes really do exist underneath', n = 2);
end $$;

do $$ begin raise notice '# All schema checks passed'; end $$;

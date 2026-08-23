-- ============================================================================
-- PlayingTime Football — schema 0001
--
-- STATUS: WRITTEN AND UNAPPLIED. This file has not been run against any
-- database. Applying it is a decision for the account owner, not something a
-- build session does on its own initiative.
--
-- Target:   Venuewise Platform (urwnbskrtoplgnkkxuvl) — the project HomeHuddle
--           already uses. PlayingTime lives in its own schema so it is purely
--           additive: nothing in `public` is read, altered or dropped here.
-- Reverse:  see 0001_playingtime_down.sql — drops the schema and nothing else.
--
-- WHY THIS IS NOT YET THE SOURCE OF TRUTH
-- V1 tracks games locally in the browser (playingtime/assets/js/store.js). A
-- parent in a stadium loses signal; a tracker that needs a round trip per tap
-- loses the game. When this schema is applied, the local store stays the write
-- path during a game and this becomes the durable copy behind it.
--
-- DESIGN NOTE (build brief §26)
-- Totals are not stored. Plays and stat events are stored, and every total is
-- derived. That is what makes quarter-by-quarter analysis, correction and later
-- analysis possible without a rebuild. `playingtime.game_units` is therefore a
-- VIEW over the play log, not a table — one source of truth, and no chance of a
-- stored total disagreeing with the plays that produced it.
-- ============================================================================

create schema if not exists playingtime;
comment on schema playingtime is
  'PlayingTime Football. Additive: owns only its own objects, reads nothing in public.';

-- ---------------------------------------------------------------------------
-- Enumerated vocabularies. Text + CHECK rather than Postgres enums: adding a
-- stat type must not need an ALTER TYPE and a deploy window.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.units (
  id    text primary key,
  label text not null
);
insert into playingtime.units (id, label) values
  ('offense', 'Offense'), ('defense', 'Defense'), ('special_teams', 'Special Teams')
on conflict (id) do nothing;

create table if not exists playingtime.stat_types (
  id        text primary key,
  label     text not null,
  unit      text not null references playingtime.units(id),
  stat_group text not null,
  -- true when the client offers the quick yardage sheet for this stat (§12)
  has_yardage boolean not null default false
);

insert into playingtime.stat_types (id, label, unit, stat_group, has_yardage) values
  -- Defense (§9)
  ('solo_tackle',     'Solo tackle',        'defense', 'Tackling',  false),
  ('assist_tackle',   'Assisted tackle',    'defense', 'Tackling',  false),
  ('tfl',             'Tackle for loss',    'defense', 'Tackling',  false),
  ('sack',            'Sack',               'defense', 'Pressure',  false),
  ('pressure',        'QB pressure',        'defense', 'Pressure',  false),
  ('pbu',             'Pass breakup',       'defense', 'Coverage',  false),
  ('interception',    'Interception',       'defense', 'Coverage',  false),
  ('forced_fumble',   'Forced fumble',      'defense', 'Takeaways', false),
  ('fumble_rec',      'Fumble recovery',    'defense', 'Takeaways', false),
  ('def_td',          'Defensive touchdown','defense', 'Scoring',   false),
  -- Offense (§10)
  ('pass_complete',   'Completion',         'offense', 'Passing',   true),
  ('pass_incomplete', 'Incompletion',       'offense', 'Passing',   false),
  ('pass_td',         'Passing touchdown',  'offense', 'Passing',   false),
  ('pass_int',        'Interception thrown','offense', 'Passing',   false),
  ('sack_taken',      'Sack taken',         'offense', 'Passing',   false),
  ('rush_att',        'Rush attempt',       'offense', 'Rushing',   true),
  ('rush_td',         'Rushing touchdown',  'offense', 'Rushing',   false),
  ('target',          'Target',             'offense', 'Receiving', false),
  ('reception',       'Reception',          'offense', 'Receiving', true),
  ('rec_td',          'Receiving touchdown','offense', 'Receiving', false),
  ('drop',            'Drop',               'offense', 'Receiving', false),
  ('two_point',       'Two-point conversion','offense','Scoring',   false),
  ('fumble',          'Fumble',             'offense', 'Ball security', false),
  -- Special teams (§11)
  ('kick_return',     'Kick return',        'special_teams', 'Returns',  true),
  ('punt_return',     'Punt return',        'special_teams', 'Returns',  true),
  ('st_tackle',       'Special teams tackle','special_teams','Coverage', false),
  ('st_td',           'Special teams touchdown','special_teams','Scoring', false),
  ('fg_made',         'Field goal made',    'special_teams', 'Kicking',  false),
  ('fg_missed',       'Field goal missed',  'special_teams', 'Kicking',  false),
  ('pat_made',        'PAT made',           'special_teams', 'Kicking',  false),
  ('pat_missed',      'PAT missed',         'special_teams', 'Kicking',  false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Account. The identity is Supabase auth; this row carries only what
-- PlayingTime itself needs. Deleting the auth user deletes everything below it.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null default '',
  email      text not null default '',
  phone      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Athletes (§25). One account tracks one or more athletes.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.athletes (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references playingtime.profiles(id) on delete cascade,
  name               text not null check (length(trim(name)) > 0),
  jersey_number      text,
  team               text,
  level              text,
  season             text,
  primary_position   text,
  secondary_position text,
  photo_url          text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists athletes_user_idx on playingtime.athletes (user_id);

-- ---------------------------------------------------------------------------
-- Seasons (§25). Optional grouping; a game's season text is denormalised onto
-- the game so history still groups correctly if no season row was ever made.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.seasons (
  id         uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references playingtime.athletes(id) on delete cascade,
  year       int  not null,
  team       text,
  created_at timestamptz not null default now(),
  unique (athlete_id, year)
);

-- ---------------------------------------------------------------------------
-- Games (§25)
-- ---------------------------------------------------------------------------
create table if not exists playingtime.games (
  id          uuid primary key default gen_random_uuid(),
  athlete_id  uuid not null references playingtime.athletes(id) on delete cascade,
  opponent    text not null default '',
  game_date   date not null,
  home_away   text not null default 'home' check (home_away in ('home', 'away')),
  location    text,
  season      text,
  status      text not null default 'in_progress'
                check (status in ('in_progress', 'final')),
  -- Score is derived from score_events; these stay null and exist only for a
  -- future import path that has a final score but no play-by-play.
  final_score_us   int,
  final_score_them int,
  created_at  timestamptz not null default now(),
  ended_at    timestamptz,
  -- The client generates ids offline; this is how a device reconciles a game it
  -- already pushed instead of creating a duplicate on the next sync.
  client_id   text,
  unique (athlete_id, client_id)
);
create index if not exists games_athlete_idx on playingtime.games (athlete_id, game_date desc);

-- ---------------------------------------------------------------------------
-- Plays (§25, §26). One row per tap of NEXT PLAY. `athlete_in` is what makes
-- participation computable; it is recorded per play, never inferred later.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.plays (
  id          uuid primary key default gen_random_uuid(),
  game_id     uuid not null references playingtime.games(id) on delete cascade,
  seq         int  not null,
  quarter     text not null check (quarter in ('Q1', 'Q2', 'Q3', 'Q4', 'OT')),
  unit        text not null references playingtime.units(id),
  athlete_in  boolean not null,
  occurred_at timestamptz not null default now(),
  client_id   text,
  unique (game_id, seq)
);
create index if not exists plays_game_idx on playingtime.plays (game_id, seq);

-- ---------------------------------------------------------------------------
-- Stat events (§25 `stats`, §26).
--
-- play_id is NULLABLE on purpose. A parent taps TACKLE a moment after tapping
-- NEXT PLAY, and the app does not ask them which play it belonged to. Guessing
-- an association would be inventing data. So each stat carries its own quarter
-- and unit, and links to a play only when a client genuinely knows.
--
-- `yards` is also nullable, and null means "not entered", not zero. A parent who
-- did not see the gain still gets the attempt counted, and reports say how many
-- are missing rather than quietly averaging in a zero.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.stats (
  id          uuid primary key default gen_random_uuid(),
  game_id     uuid not null references playingtime.games(id) on delete cascade,
  play_id     uuid references playingtime.plays(id) on delete set null,
  athlete_id  uuid not null references playingtime.athletes(id) on delete cascade,
  seq         int  not null,
  stat_type   text not null references playingtime.stat_types(id),
  quarter     text not null check (quarter in ('Q1', 'Q2', 'Q3', 'Q4', 'OT')),
  unit        text not null references playingtime.units(id),
  athlete_in  boolean not null default true,
  yards       int,
  occurred_at timestamptz not null default now(),
  client_id   text,
  unique (game_id, seq)
);
create index if not exists stats_game_idx on playingtime.stats (game_id, seq);
create index if not exists stats_athlete_idx on playingtime.stats (athlete_id, stat_type);

-- ---------------------------------------------------------------------------
-- Score events (§15). Optional; a game is complete without them.
-- ---------------------------------------------------------------------------
create table if not exists playingtime.score_events (
  id          uuid primary key default gen_random_uuid(),
  game_id     uuid not null references playingtime.games(id) on delete cascade,
  seq         int  not null,
  quarter     text not null check (quarter in ('Q1', 'Q2', 'Q3', 'Q4', 'OT')),
  side        text not null check (side in ('us', 'them')),
  points      int  not null check (points between 1 and 8),
  occurred_at timestamptz not null default now(),
  unique (game_id, seq)
);

-- ---------------------------------------------------------------------------
-- game_units (§25) — a VIEW, not a table.
--
-- The brief lists team_plays and athlete_plays as stored columns. Storing them
-- would create a second source of truth that can drift from the play log, and
-- §26 is explicit that totals are derived. Clients get the same shape either way.
--
-- security_invoker IS LOAD-BEARING, NOT A STYLE CHOICE. Without it a view runs
-- with its owner's permissions, and the owner is not subject to the RLS on
-- `plays` — so this view would hand any signed-in parent the participation of
-- every other parent's child. The verification suite caught exactly that
-- (playingtime/tests/db/verify.sql, "the derived view leaks nothing either").
-- Requires Postgres 15+; the target project is Postgres 17.
-- ---------------------------------------------------------------------------
create or replace view playingtime.game_units
with (security_invoker = true) as
select
  p.game_id,
  p.unit,
  count(*)::int                                        as team_plays,
  count(*) filter (where p.athlete_in)::int            as athlete_plays,
  case
    when count(*) = 0 then 0::numeric
    else round(count(*) filter (where p.athlete_in)::numeric * 100 / count(*), 1)
  end                                                  as participation
from playingtime.plays p
group by p.game_id, p.unit;

comment on view playingtime.game_units is
  'Derived participation per game per unit. Never stored, and security_invoker so '
  'the caller''s RLS applies — see migration header.';

-- ---------------------------------------------------------------------------
-- Row Level Security.
--
-- FORCE, so the table owner is subject to its own policies too. Every policy is
-- ownership by way of the athlete's user_id; there is no "any signed-in user can
-- read" path anywhere in this schema. Children of a game are reached through the
-- game, so a single ownership rule governs the whole tree.
-- ---------------------------------------------------------------------------
alter table playingtime.profiles     enable row level security;
alter table playingtime.athletes     enable row level security;
alter table playingtime.seasons      enable row level security;
alter table playingtime.games        enable row level security;
alter table playingtime.plays        enable row level security;
alter table playingtime.stats        enable row level security;
alter table playingtime.score_events enable row level security;

alter table playingtime.profiles     force row level security;
alter table playingtime.athletes     force row level security;
alter table playingtime.seasons      force row level security;
alter table playingtime.games        force row level security;
alter table playingtime.plays        force row level security;
alter table playingtime.stats        force row level security;
alter table playingtime.score_events force row level security;

-- Reference vocabularies are readable by any signed-in client and writable by
-- none of them.
alter table playingtime.units      enable row level security;
alter table playingtime.stat_types enable row level security;
create policy units_read      on playingtime.units      for select to authenticated using (true);
create policy stat_types_read on playingtime.stat_types for select to authenticated using (true);

-- Profile: you, and only you.
create policy profiles_own on playingtime.profiles
  for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Athletes: owned directly.
create policy athletes_own on playingtime.athletes
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy seasons_own on playingtime.seasons
  for all to authenticated
  using (exists (select 1 from playingtime.athletes a
                  where a.id = seasons.athlete_id and a.user_id = (select auth.uid())))
  with check (exists (select 1 from playingtime.athletes a
                  where a.id = seasons.athlete_id and a.user_id = (select auth.uid())));

create policy games_own on playingtime.games
  for all to authenticated
  using (exists (select 1 from playingtime.athletes a
                  where a.id = games.athlete_id and a.user_id = (select auth.uid())))
  with check (exists (select 1 from playingtime.athletes a
                  where a.id = games.athlete_id and a.user_id = (select auth.uid())));

create policy plays_own on playingtime.plays
  for all to authenticated
  using (exists (select 1 from playingtime.games g
                  join playingtime.athletes a on a.id = g.athlete_id
                 where g.id = plays.game_id and a.user_id = (select auth.uid())))
  with check (exists (select 1 from playingtime.games g
                  join playingtime.athletes a on a.id = g.athlete_id
                 where g.id = plays.game_id and a.user_id = (select auth.uid())));

create policy stats_own on playingtime.stats
  for all to authenticated
  using (exists (select 1 from playingtime.games g
                  join playingtime.athletes a on a.id = g.athlete_id
                 where g.id = stats.game_id and a.user_id = (select auth.uid())))
  with check (exists (select 1 from playingtime.games g
                  join playingtime.athletes a on a.id = g.athlete_id
                 where g.id = stats.game_id and a.user_id = (select auth.uid())));

create policy score_events_own on playingtime.score_events
  for all to authenticated
  using (exists (select 1 from playingtime.games g
                  join playingtime.athletes a on a.id = g.athlete_id
                 where g.id = score_events.game_id and a.user_id = (select auth.uid())))
  with check (exists (select 1 from playingtime.games g
                  join playingtime.athletes a on a.id = g.athlete_id
                 where g.id = score_events.game_id and a.user_id = (select auth.uid())));

-- Grants. The view is security_invoker, so a caller only ever sees the rows the
-- policies on `plays` would have let them read directly.
grant usage on schema playingtime to authenticated;
grant select on playingtime.units, playingtime.stat_types to authenticated;
grant select, insert, update, delete on
  playingtime.profiles, playingtime.athletes, playingtime.seasons,
  playingtime.games, playingtime.plays, playingtime.stats, playingtime.score_events
  to authenticated;
grant select on playingtime.game_units to authenticated;

-- A new sign-up gets a profile row without the client having to remember to.
create or replace function playingtime.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into playingtime.profiles (id, email, name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- NOTE: intentionally NOT created here. A trigger on auth.users is shared with
-- every other product in this Supabase project, so adding one is a
-- project-wide change that needs its own review alongside HomeHuddle:
--
--   create trigger on_auth_user_created_playingtime
--     after insert on auth.users
--     for each row execute function playingtime.handle_new_user();

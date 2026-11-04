-- Bridge between the two parallel athlete systems:
-- HomeHuddle's lightweight `players` (live calendar sync) and
-- AthleteHuddle's richer `athletes` profile. 1:1 link.
create table public.athlete_player_links (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz default now(),
  unique (athlete_id),
  unique (player_id)
);
create index idx_athlete_player_links_athlete on public.athlete_player_links(athlete_id);
create index idx_athlete_player_links_player on public.athlete_player_links(player_id);

-- Link coach_connections to the real coaches table instead of
-- relying solely on plain-text coach_name/coach_email.
alter table public.coach_connections
  add column coach_id_link uuid references public.coaches(id) on delete set null;
create index idx_coach_connections_coach_id_link on public.coach_connections(coach_id_link);

-- Let a facility booking/open-slot claim optionally point at a real
-- AthleteHuddle profile, so FacilityHuddle activity can eventually
-- surface inside that athlete's (and family's) calendar view.
alter table public.bookings
  add column athlete_id uuid references public.athletes(id) on delete set null;
create index idx_bookings_athlete_id on public.bookings(athlete_id);

alter table public.open_slots
  add column claimed_by_athlete_id uuid references public.athletes(id) on delete set null;
create index idx_open_slots_claimed_athlete_id on public.open_slots(claimed_by_athlete_id);
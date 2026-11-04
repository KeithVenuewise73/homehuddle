alter table public.player_teams
  add column if not exists team_id uuid references public.teams(id) on delete set null;

alter table public.game_scores
  add column if not exists home_team_id uuid references public.teams(id) on delete set null;

alter table public.game_scores
  add column if not exists away_team_id uuid references public.teams(id) on delete set null;

create index if not exists player_teams_team_id_idx  on public.player_teams(team_id);
create index if not exists game_scores_home_team_idx on public.game_scores(home_team_id);
create index if not exists game_scores_away_team_idx on public.game_scores(away_team_id);

comment on column public.player_teams.team_id is
  'Nullable during Phase 1. team_name remains authoritative until reconciled.';
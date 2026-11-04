-- family_members had no age information, so no age rule could be enforced
-- server-side. Link to players, where birth_year already lives.
alter table public.family_members
  add column if not exists player_id uuid references public.players(id) on delete set null;

create index if not exists family_members_player_idx
  on public.family_members (player_id) where player_id is not null;

-- Backfill the existing name-matched rows.
update public.family_members fm
set player_id = p.id
from public.players p
join public.family_players fp on fp.player_id = p.id
where fm.player_id is null
  and fm.role = 'player'
  and fp.family_id = fm.family_id
  and lower(btrim(p.name)) = lower(btrim(fm.name));

-- Age of a member, or null when unknown. birth_year is text in players.
create or replace function public.member_age(p_member_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
           when p.birth_year ~ '^\d{4}$'
             then extract(year from now())::int - p.birth_year::int
           else null
         end
  from public.family_members fm
  join public.players p on p.id = fm.player_id
  where fm.id = p_member_id;
$$;
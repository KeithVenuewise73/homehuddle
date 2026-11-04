
-- Close public/anon read of children's names + teams.
-- Nothing reads these tables directly; all legitimate access is via SECURITY DEFINER
-- RPCs (onboarding, my_athletes, my_athlete_candidates, etc.) which bypass RLS.
-- Grandparent calendar sharing runs on family_access/events — untouched.
DROP POLICY IF EXISTS "Allow public select on players"         ON public.players;
DROP POLICY IF EXISTS anon_read_players                        ON public.players;
DROP POLICY IF EXISTS "Allow public select on player_teams"    ON public.player_teams;
DROP POLICY IF EXISTS anon_read_player_teams                   ON public.player_teams;
DROP POLICY IF EXISTS "Allow public select on family_players"  ON public.family_players;
DROP POLICY IF EXISTS anon_read_family_players                 ON public.family_players;

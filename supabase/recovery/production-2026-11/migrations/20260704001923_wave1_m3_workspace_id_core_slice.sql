begin;

alter table public.families add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_families_workspace on public.families(workspace_id);
update public.families set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.family_members add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_family_members_workspace on public.family_members(workspace_id);
update public.family_members set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.family_players add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_family_players_workspace on public.family_players(workspace_id);
update public.family_players set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.players add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_players_workspace on public.players(workspace_id);
update public.players set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.player_teams add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_player_teams_workspace on public.player_teams(workspace_id);
update public.player_teams set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.feeds add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_feeds_workspace on public.feeds(workspace_id);
update public.feeds set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.events add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_events_workspace on public.events(workspace_id);
update public.events set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.family_events add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_family_events_workspace on public.family_events(workspace_id);
update public.family_events set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.calendar_events add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_calendar_events_workspace on public.calendar_events(workspace_id);
update public.calendar_events set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.calendar_event_participants add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_cal_event_participants_workspace on public.calendar_event_participants(workspace_id);
update public.calendar_event_participants set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.reminders add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_reminders_workspace on public.reminders(workspace_id);
update public.reminders set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

alter table public.subscriptions add column if not exists workspace_id uuid
  references public.business_workspaces(id) on delete set null;
create index if not exists idx_subscriptions_workspace on public.subscriptions(workspace_id);
update public.subscriptions set workspace_id =
  (select id from public.business_workspaces where slug='homehuddle') where workspace_id is null;

commit;
-- Shared event layer for the Venuewise ecosystem.
-- One canonical event row, regardless of which module created it,
-- plus a many-to-many participants table so the same event can
-- appear on family calendars, athlete profiles, coach pages,
-- organization pages, and facility/marketplace listings without
-- duplicate entry.
--
-- IMPORTANT: this table is populated alongside existing source
-- tables (events, organization_events, clinics, facility_events,
-- etc.), not instead of them. Source tables are untouched.

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  source_module text not null check (source_module in (
    'homehuddle','athletehuddle','coacheshuddle','organizationhuddle','facilityhuddle','tournamenthuddle'
  )),
  source_table text not null,
  source_id text not null,
  title text not null,
  description text,
  event_type text,
  start_time timestamptz not null,
  end_time timestamptz,
  location_name text,
  location_address text,
  organization_id uuid references public.organizations(id) on delete set null,
  coach_id uuid references public.coaches(id) on delete set null,
  facility_id uuid references public.facilities(id) on delete set null,
  is_public boolean default false,
  status text default 'active' check (status in ('active','cancelled','completed')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  -- Prevents the exact same source row from ever being mirrored twice,
  -- regardless of which sync run or module inserted it.
  unique (source_module, source_table, source_id)
);

create index idx_calendar_events_start_time on public.calendar_events(start_time);
create index idx_calendar_events_organization_id on public.calendar_events(organization_id);
create index idx_calendar_events_coach_id on public.calendar_events(coach_id);
create index idx_calendar_events_facility_id on public.calendar_events(facility_id);
create index idx_calendar_events_source on public.calendar_events(source_module, source_table, source_id);

create table public.calendar_event_participants (
  id uuid primary key default gen_random_uuid(),
  calendar_event_id uuid not null references public.calendar_events(id) on delete cascade,
  athlete_id uuid references public.athletes(id) on delete cascade,
  family_id uuid references public.families(id) on delete cascade,
  participant_role text not null check (participant_role in (
    'registrant','roster_member','claimed_by','host'
  )),
  created_at timestamptz default now(),
  -- A given athlete (or family, if no athlete is specified) should
  -- only be attached to a given event once per role.
  unique (calendar_event_id, athlete_id, family_id, participant_role)
);

create index idx_cep_calendar_event_id on public.calendar_event_participants(calendar_event_id);
create index idx_cep_athlete_id on public.calendar_event_participants(athlete_id);
create index idx_cep_family_id on public.calendar_event_participants(family_id);
create table if not exists public.teams (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid references public.organizations(id) on delete set null,
  name             text not null,
  age_group        text,
  level            text,
  season           text,
  sport            text,
  external_ref     text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint teams_level_check
    check (level is null or level in ('house','travel','elite','other'))
);

alter table public.teams enable row level security;

create index if not exists teams_organization_id_idx on public.teams(organization_id);
create index if not exists teams_season_idx          on public.teams(season);
create index if not exists teams_external_ref_idx    on public.teams(external_ref);

comment on table public.teams is
  'Canonical team entity: organization -> team -> age group -> house/travel. Added Phase 1 2026-08-27. RLS enabled with no policies (locked until Phase 2).';
begin;

create table if not exists public.business_workspaces (
  id                  uuid primary key default gen_random_uuid(),
  slug                text not null unique,
  name                text not null,
  workspace_type      text not null default 'business_client'
                        check (workspace_type in
                          ('platform','holding','sports_org','home_services',
                           'media_brand','review_platform','education','business_client')),
  parent_workspace_id uuid references public.business_workspaces(id) on delete restrict,
  industry_pack       text,
  status              text not null default 'active'
                        check (status in ('active','suspended','archived')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists idx_business_workspaces_parent on public.business_workspaces(parent_workspace_id);

create table if not exists public.workspace_members (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
  person_id    uuid not null references public.people(id) on delete cascade,
  status       text not null default 'active' check (status in ('active','pending','revoked')),
  created_at   timestamptz not null default now(),
  unique (workspace_id, person_id)
);
create index if not exists idx_workspace_members_workspace on public.workspace_members(workspace_id);
create index if not exists idx_workspace_members_person    on public.workspace_members(person_id);

create table if not exists public.workspace_roles (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
  person_id    uuid not null references public.people(id) on delete cascade,
  role         text not null
                 check (role in ('owner','admin','staff','coach','customer','viewer')),
  created_at   timestamptz not null default now(),
  unique (workspace_id, person_id, role)
);
create index if not exists idx_workspace_roles_workspace on public.workspace_roles(workspace_id);
create index if not exists idx_workspace_roles_person    on public.workspace_roles(person_id);

create table if not exists public.workspace_services (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.business_workspaces(id) on delete cascade,
  name         text not null,
  service_type text,
  price        numeric,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists idx_workspace_services_workspace on public.workspace_services(workspace_id);

create table if not exists public.workspace_branding (
  workspace_id  uuid primary key references public.business_workspaces(id) on delete cascade,
  logo_url      text,
  primary_color text,
  theme         jsonb not null default '{}'::jsonb,
  footer_line   text not null default 'Powered by Venuewise',
  custom_domain text,
  updated_at    timestamptz not null default now()
);

create table if not exists public.workspace_settings (
  workspace_id uuid primary key references public.business_workspaces(id) on delete cascade,
  settings     jsonb not null default '{}'::jsonb,
  updated_at   timestamptz not null default now()
);

alter table public.business_workspaces enable row level security;
alter table public.workspace_members   enable row level security;
alter table public.workspace_roles     enable row level security;
alter table public.workspace_services  enable row level security;
alter table public.workspace_branding  enable row level security;
alter table public.workspace_settings  enable row level security;

insert into public.business_workspaces (slug, name, workspace_type, industry_pack) values
  ('venuewise',  'Venuewise',            'platform',   null),
  ('homehuddle', 'HomeHuddle',           'sports_org', 'sports'),
  ('ddh',        'DDH Operating Company','holding',    null)
on conflict (slug) do nothing;

insert into public.business_workspaces (slug, name, workspace_type, parent_workspace_id, industry_pack)
select 'ddh-athlete-development', 'DDH Athlete Development', 'sports_org', p.id, 'sports'
from public.business_workspaces p where p.slug = 'ddh'
on conflict (slug) do nothing;

insert into public.business_workspaces (slug, name, workspace_type, parent_workspace_id, industry_pack)
select 'ddh-home-services', 'DDH Home Services', 'home_services', p.id, 'home_services'
from public.business_workspaces p where p.slug = 'ddh'
on conflict (slug) do nothing;

insert into public.workspace_branding (workspace_id, footer_line)
select id, 'Powered by Venuewise' from public.business_workspaces
on conflict (workspace_id) do nothing;

insert into public.workspace_settings (workspace_id, settings)
select id, '{}'::jsonb from public.business_workspaces
on conflict (workspace_id) do nothing;

commit;
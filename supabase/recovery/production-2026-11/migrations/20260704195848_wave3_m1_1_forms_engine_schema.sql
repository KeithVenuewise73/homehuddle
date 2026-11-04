begin;

create table if not exists public.form_templates (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid references public.business_workspaces(id) on delete cascade,
  industry_pack text,
  key           text not null,
  name          text not null,
  description   text,
  subject_type  text,
  version       integer not null default 1 check (version >= 1),
  status        text not null default 'draft' check (status in ('draft','published','archived')),
  schema        jsonb not null default '{}'::jsonb,
  created_by    uuid references public.people(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists uq_form_templates_ws_key_ver
  on public.form_templates(workspace_id, key, version) where workspace_id is not null;
create unique index if not exists uq_form_templates_global_key_ver
  on public.form_templates(key, version) where workspace_id is null;
create index if not exists idx_form_templates_workspace on public.form_templates(workspace_id);
create index if not exists idx_form_templates_pack on public.form_templates(industry_pack);

create table if not exists public.form_sections (
  id               uuid primary key default gen_random_uuid(),
  form_template_id uuid not null references public.form_templates(id) on delete cascade,
  key              text not null,
  name             text,
  description      text,
  position         integer not null default 0,
  repeatable       boolean not null default false,
  min_repeat       integer not null default 0,
  max_repeat       integer,
  visible_if       jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  unique (form_template_id, key)
);
create index if not exists idx_form_sections_template on public.form_sections(form_template_id, position);

create table if not exists public.form_fields (
  id               uuid primary key default gen_random_uuid(),
  form_template_id uuid not null references public.form_templates(id) on delete cascade,
  section_id       uuid not null references public.form_sections(id) on delete cascade,
  key              text not null,
  label            text not null,
  field_type       text not null check (field_type in (
                     'text','textarea','number','integer','date','datetime','time',
                     'select','multiselect','radio','checkbox','boolean','email','phone',
                     'url','file','signature','info')),
  position         integer not null default 0,
  required         boolean not null default false,
  placeholder      text,
  help_text        text,
  options          jsonb not null default '[]'::jsonb,
  validation       jsonb not null default '{}'::jsonb,
  visible_if       jsonb not null default '{}'::jsonb,
  default_value    jsonb,
  created_at       timestamptz not null default now(),
  unique (form_template_id, key)
);
create index if not exists idx_form_fields_section on public.form_fields(section_id, position);

create table if not exists public.form_submissions (
  id                   uuid primary key default gen_random_uuid(),
  workspace_id         uuid not null references public.business_workspaces(id) on delete cascade,
  form_template_id     uuid not null references public.form_templates(id) on delete restrict,
  template_version     integer not null,
  subject_type         text,
  subject_id           text,
  workflow_instance_id uuid references public.workflow_instances(id) on delete set null,
  workflow_task_id     uuid references public.workflow_tasks(id) on delete set null,
  status               text not null default 'draft' check (status in ('draft','submitted','completed','void')),
  data                 jsonb not null default '{}'::jsonb,
  created_by           uuid references public.people(id) on delete set null,
  submitted_by         uuid references public.people(id) on delete set null,
  submitted_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index if not exists idx_form_submissions_workspace on public.form_submissions(workspace_id);
create index if not exists idx_form_submissions_template on public.form_submissions(form_template_id);
create index if not exists idx_form_submissions_wf_instance on public.form_submissions(workflow_instance_id);
create index if not exists idx_form_submissions_wf_task on public.form_submissions(workflow_task_id);
create index if not exists idx_form_submissions_status on public.form_submissions(status);
create index if not exists idx_form_submissions_subject on public.form_submissions(subject_type, subject_id);

create table if not exists public.form_submission_events (
  id              uuid primary key default gen_random_uuid(),
  submission_id   uuid not null references public.form_submissions(id) on delete cascade,
  workspace_id    uuid not null references public.business_workspaces(id) on delete cascade,
  event_type      text not null,
  actor_person_id uuid references public.people(id) on delete set null,
  payload         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists idx_form_sub_events_submission on public.form_submission_events(submission_id);
create index if not exists idx_form_sub_events_workspace on public.form_submission_events(workspace_id);
create index if not exists idx_form_sub_events_created on public.form_submission_events(created_at);

alter table public.form_templates         enable row level security;
alter table public.form_sections          enable row level security;
alter table public.form_fields            enable row level security;
alter table public.form_submissions       enable row level security;
alter table public.form_submission_events enable row level security;

create or replace function public.readable_form_template_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from public.form_templates
  where (workspace_id is null and status='published')
     or workspace_id in (select public.current_workspace_ids());
$$;

create policy ft_select on public.form_templates
  for select to authenticated
  using (id in (select public.readable_form_template_ids()));

create policy fsec_select on public.form_sections
  for select to authenticated
  using (form_template_id in (select public.readable_form_template_ids()));

create policy ffld_select on public.form_fields
  for select to authenticated
  using (form_template_id in (select public.readable_form_template_ids()));

create policy fsub_select on public.form_submissions
  for select to authenticated
  using (
    workspace_id in (select public.current_workspace_ids())
    or created_by = public.current_person_id()
    or submitted_by = public.current_person_id()
  );

create policy fsube_select on public.form_submission_events
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

commit;
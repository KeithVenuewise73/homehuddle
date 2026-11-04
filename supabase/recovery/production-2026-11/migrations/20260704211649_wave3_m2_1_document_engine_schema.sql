begin;

create table if not exists public.document_templates (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid references public.business_workspaces(id) on delete cascade,
  industry_pack text,
  key           text not null,
  name          text not null,
  description   text,
  subject_type  text,
  version       integer not null default 1 check (version >= 1),
  status        text not null default 'draft' check (status in ('draft','published','archived')),
  output_format text not null default 'pdf' check (output_format in ('pdf','html','docx')),
  content_spec  jsonb not null default '{}'::jsonb,
  html_body     text,
  merge_schema  jsonb not null default '{}'::jsonb,
  created_by    uuid references public.people(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists uq_doc_templates_ws_key_ver
  on public.document_templates(workspace_id, key, version) where workspace_id is not null;
create unique index if not exists uq_doc_templates_global_key_ver
  on public.document_templates(key, version) where workspace_id is null;
create index if not exists idx_doc_templates_workspace on public.document_templates(workspace_id);
create index if not exists idx_doc_templates_pack on public.document_templates(industry_pack);

create table if not exists public.documents (
  id                   uuid primary key default gen_random_uuid(),
  workspace_id         uuid not null references public.business_workspaces(id) on delete cascade,
  document_template_id uuid not null references public.document_templates(id) on delete restrict,
  template_version     integer not null,
  workflow_instance_id uuid references public.workflow_instances(id) on delete set null,
  workflow_task_id     uuid references public.workflow_tasks(id) on delete set null,
  subject_type         text,
  subject_id           text,
  name                 text not null,
  status               text not null default 'generated'
                         check (status in ('draft','generated','approved','rejected','signed','void')),
  current_version      integer not null default 1,
  generated_by         uuid references public.people(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index if not exists idx_documents_workspace on public.documents(workspace_id);
create index if not exists idx_documents_template on public.documents(document_template_id);
create index if not exists idx_documents_wf_instance on public.documents(workflow_instance_id);
create index if not exists idx_documents_status on public.documents(status);
create index if not exists idx_documents_subject on public.documents(subject_type, subject_id);

create table if not exists public.document_versions (
  id                 uuid primary key default gen_random_uuid(),
  document_id        uuid not null references public.documents(id) on delete cascade,
  workspace_id       uuid not null references public.business_workspaces(id) on delete cascade,
  version            integer not null,
  output_format      text not null default 'pdf',
  storage_bucket     text not null default 'documents',
  storage_path       text,
  file_size          bigint,
  content_hash       text,
  form_submission_id uuid references public.form_submissions(id) on delete set null,
  merge_context      jsonb not null default '{}'::jsonb,
  generated_by       uuid references public.people(id) on delete set null,
  generated_at       timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  unique (document_id, version)
);
create index if not exists idx_doc_versions_document on public.document_versions(document_id);
create index if not exists idx_doc_versions_workspace on public.document_versions(workspace_id);

create table if not exists public.document_approvals (
  id                  uuid primary key default gen_random_uuid(),
  document_id         uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete set null,
  workspace_id        uuid not null references public.business_workspaces(id) on delete cascade,
  required_role       text,
  approver_person_id  uuid references public.people(id) on delete set null,
  decision            text not null default 'pending' check (decision in ('pending','approved','rejected')),
  signature_ref       jsonb not null default '{}'::jsonb,
  comment             text,
  decided_at          timestamptz,
  created_at          timestamptz not null default now()
);
create index if not exists idx_doc_approvals_document on public.document_approvals(document_id);
create index if not exists idx_doc_approvals_approver on public.document_approvals(approver_person_id);

create table if not exists public.document_events (
  id              uuid primary key default gen_random_uuid(),
  document_id     uuid not null references public.documents(id) on delete cascade,
  workspace_id    uuid not null references public.business_workspaces(id) on delete cascade,
  event_type      text not null,
  actor_person_id uuid references public.people(id) on delete set null,
  payload         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists idx_doc_events_document on public.document_events(document_id);
create index if not exists idx_doc_events_workspace on public.document_events(workspace_id);
create index if not exists idx_doc_events_created on public.document_events(created_at);

alter table public.document_templates enable row level security;
alter table public.documents          enable row level security;
alter table public.document_versions  enable row level security;
alter table public.document_approvals enable row level security;
alter table public.document_events    enable row level security;

create or replace function public.readable_document_template_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from public.document_templates
  where (workspace_id is null and status='published')
     or workspace_id in (select public.current_workspace_ids());
$$;

create policy dt_select on public.document_templates
  for select to authenticated
  using (id in (select public.readable_document_template_ids()));

create policy doc_select on public.documents
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

create policy docv_select on public.document_versions
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

create policy doca_select on public.document_approvals
  for select to authenticated
  using (
    workspace_id in (select public.current_workspace_ids())
    or approver_person_id = public.current_person_id()
  );

create policy doce_select on public.document_events
  for select to authenticated
  using (workspace_id in (select public.current_workspace_ids()));

insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

commit;
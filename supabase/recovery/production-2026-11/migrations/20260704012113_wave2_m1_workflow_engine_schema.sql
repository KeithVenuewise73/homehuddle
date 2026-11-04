begin;

create table if not exists public.workflow_templates (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid references public.business_workspaces(id) on delete cascade,
  industry_pack text,
  key           text not null,
  name          text not null,
  description   text,
  subject_type  text not null,
  version       integer not null default 1 check (version >= 1),
  status        text not null default 'draft'
                  check (status in ('draft','published','archived')),
  definition    jsonb not null default '{}'::jsonb,
  created_by    uuid references public.people(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists uq_wf_templates_ws_key_ver
  on public.workflow_templates(workspace_id, key, version) where workspace_id is not null;
create unique index if not exists uq_wf_templates_global_key_ver
  on public.workflow_templates(key, version) where workspace_id is null;
create index if not exists idx_wf_templates_workspace on public.workflow_templates(workspace_id);
create index if not exists idx_wf_templates_subject   on public.workflow_templates(subject_type);
create index if not exists idx_wf_templates_pack      on public.workflow_templates(industry_pack);

create table if not exists public.workflow_template_stages (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid not null references public.workflow_templates(id) on delete cascade,
  key          text not null,
  name         text not null,
  position     integer not null default 0,
  advance_rule jsonb not null default '{"when":"all_required_tasks_complete"}'::jsonb,
  sla_days     numeric,
  on_enter     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  unique (template_id, key)
);
create index if not exists idx_wf_tmpl_stages_template on public.workflow_template_stages(template_id, position);

create table if not exists public.workflow_template_tasks (
  id              uuid primary key default gen_random_uuid(),
  template_id     uuid not null references public.workflow_templates(id) on delete cascade,
  stage_id        uuid not null references public.workflow_template_stages(id) on delete cascade,
  key             text not null,
  name            text not null,
  task_type       text not null
                    check (task_type in
                      ('manual','approval','calendar','notification','document','form','automation')),
  assignee_rule   jsonb not null default '{}'::jsonb,
  due_offset_days numeric,
  required        boolean not null default true,
  config          jsonb not null default '{}'::jsonb,
  position        integer not null default 0,
  created_at      timestamptz not null default now(),
  unique (template_id, key)
);
create index if not exists idx_wf_tmpl_tasks_stage on public.workflow_template_tasks(stage_id);

create table if not exists public.workflow_instances (
  id               uuid primary key default gen_random_uuid(),
  workspace_id     uuid not null references public.business_workspaces(id) on delete cascade,
  template_id      uuid not null references public.workflow_templates(id) on delete restrict,
  template_version integer not null,
  subject_type     text not null,
  subject_id       text,
  title            text,
  status           text not null default 'active'
                     check (status in ('active','completed','cancelled','on_hold')),
  current_stage_id uuid,
  context          jsonb not null default '{}'::jsonb,
  due_at           timestamptz,
  started_by       uuid references public.people(id) on delete set null,
  started_at       timestamptz not null default now(),
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_wf_instances_workspace on public.workflow_instances(workspace_id);
create index if not exists idx_wf_instances_template  on public.workflow_instances(template_id);
create index if not exists idx_wf_instances_status    on public.workflow_instances(status);
create index if not exists idx_wf_instances_subject   on public.workflow_instances(subject_type, subject_id);
create index if not exists idx_wf_instances_due       on public.workflow_instances(due_at);

create table if not exists public.workflow_instance_stages (
  id                uuid primary key default gen_random_uuid(),
  instance_id       uuid not null references public.workflow_instances(id) on delete cascade,
  workspace_id      uuid not null references public.business_workspaces(id) on delete cascade,
  template_stage_id uuid references public.workflow_template_stages(id) on delete set null,
  key               text not null,
  name              text not null,
  position          integer not null default 0,
  status            text not null default 'pending'
                      check (status in ('pending','active','complete','skipped')),
  entered_at        timestamptz,
  completed_at      timestamptz,
  created_at        timestamptz not null default now()
);
create index if not exists idx_wf_inst_stages_instance on public.workflow_instance_stages(instance_id, position);
create index if not exists idx_wf_inst_stages_workspace on public.workflow_instance_stages(workspace_id);

alter table public.workflow_instances
  add constraint workflow_instances_current_stage_fk
  foreign key (current_stage_id) references public.workflow_instance_stages(id) on delete set null;

create table if not exists public.workflow_tasks (
  id                 uuid primary key default gen_random_uuid(),
  instance_id        uuid not null references public.workflow_instances(id) on delete cascade,
  instance_stage_id  uuid references public.workflow_instance_stages(id) on delete cascade,
  template_task_id   uuid references public.workflow_template_tasks(id) on delete set null,
  workspace_id       uuid not null references public.business_workspaces(id) on delete cascade,
  key                text not null,
  name               text not null,
  task_type          text not null
                       check (task_type in
                         ('manual','approval','calendar','notification','document','form','automation')),
  status             text not null default 'pending'
                       check (status in ('pending','in_progress','blocked','complete','skipped','rejected')),
  assignee_person_id uuid references public.people(id) on delete set null,
  assignee_role      text,
  due_at             timestamptz,
  required           boolean not null default true,
  config             jsonb not null default '{}'::jsonb,
  result             jsonb not null default '{}'::jsonb,
  effect_ref         jsonb not null default '{}'::jsonb,
  completed_by       uuid references public.people(id) on delete set null,
  completed_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists idx_wf_tasks_instance  on public.workflow_tasks(instance_id);
create index if not exists idx_wf_tasks_stage     on public.workflow_tasks(instance_stage_id);
create index if not exists idx_wf_tasks_assignee  on public.workflow_tasks(assignee_person_id);
create index if not exists idx_wf_tasks_status    on public.workflow_tasks(status);
create index if not exists idx_wf_tasks_due       on public.workflow_tasks(due_at);
create index if not exists idx_wf_tasks_workspace on public.workflow_tasks(workspace_id);

create table if not exists public.workflow_approvals (
  id                 uuid primary key default gen_random_uuid(),
  task_id            uuid not null references public.workflow_tasks(id) on delete cascade,
  instance_id        uuid not null references public.workflow_instances(id) on delete cascade,
  workspace_id       uuid not null references public.business_workspaces(id) on delete cascade,
  required_role      text,
  approver_person_id uuid references public.people(id) on delete set null,
  decision           text not null default 'pending'
                       check (decision in ('pending','approved','rejected')),
  comment            text,
  decided_at         timestamptz,
  created_at         timestamptz not null default now()
);
create index if not exists idx_wf_approvals_instance on public.workflow_approvals(instance_id);
create index if not exists idx_wf_approvals_task     on public.workflow_approvals(task_id);
create index if not exists idx_wf_approvals_approver on public.workflow_approvals(approver_person_id);

create table if not exists public.workflow_events (
  id              uuid primary key default gen_random_uuid(),
  instance_id     uuid not null references public.workflow_instances(id) on delete cascade,
  task_id         uuid references public.workflow_tasks(id) on delete set null,
  workspace_id    uuid not null references public.business_workspaces(id) on delete cascade,
  event_type      text not null,
  actor_person_id uuid references public.people(id) on delete set null,
  payload         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists idx_wf_events_instance   on public.workflow_events(instance_id);
create index if not exists idx_wf_events_workspace  on public.workflow_events(workspace_id);
create index if not exists idx_wf_events_created    on public.workflow_events(created_at);
create index if not exists idx_wf_events_type       on public.workflow_events(event_type);

alter table public.workflow_templates        enable row level security;
alter table public.workflow_template_stages  enable row level security;
alter table public.workflow_template_tasks   enable row level security;
alter table public.workflow_instances        enable row level security;
alter table public.workflow_instance_stages  enable row level security;
alter table public.workflow_tasks            enable row level security;
alter table public.workflow_approvals        enable row level security;
alter table public.workflow_events           enable row level security;

commit;
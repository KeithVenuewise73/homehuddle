alter table public.calendar_events
  add column if not exists is_conflict boolean not null default false,
  add column if not exists is_duplicate boolean not null default false;
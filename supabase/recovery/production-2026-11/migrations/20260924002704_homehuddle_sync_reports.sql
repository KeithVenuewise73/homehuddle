-- Permanent record of every sync-schedules run (approved by Keith 2026-09-23).
-- pg_net keeps HTTP responses for only 6 hours, and before this change the
-- cron caller gave up after 5 s, so every sync report was discarded.

create table public.sync_reports (
  id          bigint generated always as identity primary key,
  request_id  bigint not null unique,           -- net.http_post() request id
  started_at  timestamptz not null default now(),
  captured_at timestamptz,
  outcome     text not null default 'running'
              check (outcome in ('running','ok','http_error','timed_out','failed','lost')),
  status_code int,
  error       text,
  report      jsonb,                            -- the function's JSON summary, when parseable
  raw_body    text                              -- kept only when the body is not JSON
);
comment on table public.sync_reports is
  'One row per sync-schedules run: what each calendar feed returned. Written by cron job 6 and capture_sync_reports(). Internal; no client access.';
create index sync_reports_started_at_idx on public.sync_reports (started_at desc);

alter table public.sync_reports enable row level security;
revoke all on public.sync_reports from anon, authenticated;

create or replace function public.capture_sync_reports()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  j jsonb;
  n integer := 0;
begin
  for r in
    select s.id, h.status_code, h.timed_out, h.error_msg, h.content
      from public.sync_reports s
      join net._http_response h on h.id = s.request_id
     where s.outcome = 'running'
  loop
    begin
      j := r.content::jsonb;
    exception when others then
      j := null;
    end;
    update public.sync_reports set
      captured_at = now(),
      status_code = r.status_code,
      error       = r.error_msg,
      report      = j,
      raw_body    = case when j is null then left(r.content, 4000) end,
      outcome     = case
                      when r.timed_out then 'timed_out'
                      when r.error_msg is not null then 'failed'
                      when r.status_code between 200 and 299 then 'ok'
                      else 'http_error'
                    end
     where id = r.id;
    n := n + 1;
  end loop;

  -- pg_net deletes responses after 6 hours; anything still unmatched is gone.
  update public.sync_reports
     set outcome = 'lost', captured_at = now()
   where outcome = 'running' and started_at < now() - interval '6 hours';

  return n;
end;
$$;
revoke all on function public.capture_sync_reports() from public, anon, authenticated;

-- Record the request id of every sync run. Edited in place so the stored
-- service key in the job never leaves the database.
select cron.alter_job(
  6,
  command := replace(command, 'select net.http_post(', 'insert into public.sync_reports (request_id) select net.http_post(')
)
from cron.job
where jobid = 6 and command not like '%sync_reports%';

select cron.schedule('capture-sync-reports', '*/5 * * * *', 'select public.capture_sync_reports();');
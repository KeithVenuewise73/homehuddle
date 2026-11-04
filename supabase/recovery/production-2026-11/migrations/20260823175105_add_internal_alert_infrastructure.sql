-- Recipients of internal business alerts (staff/founder), separate from end-user SMS.
create table if not exists public.alert_recipients (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  phone text not null,
  active boolean not null default true,
  alert_leads boolean not null default true,
  alert_bookings boolean not null default true,
  alert_submissions boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.alert_recipients enable row level security;
-- No policies: service_role only. Nothing client-side can read staff phone numbers.

create unique index if not exists alert_recipients_phone_uniq on public.alert_recipients (phone);

-- Fan an internal alert out to every active recipient by writing into the existing outbox.
-- The send-sms-outbox cron (every 2 min) picks these up with no further changes.
create or replace function public.enqueue_internal_alert(
  p_kind text,
  p_event_ref text,
  p_message text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  insert into public.sms_outbox (person_id, phone, event_ref, change_hash, message, status)
  select null, r.phone, p_event_ref, md5(p_message || r.phone), left(p_message, 480), 'pending'
  from public.alert_recipients r
  where r.active
    and case p_kind
          when 'lead'       then r.alert_leads
          when 'booking'    then r.alert_bookings
          when 'submission' then r.alert_submissions
          else true
        end
  on conflict do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
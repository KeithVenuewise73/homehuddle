-- Candidate only. Existing tables/IDs are reused. No partner/customer seed data.
begin;
create schema if not exists rink_private;
revoke all on schema rink_private from public;
grant usage on schema rink_private to anon, authenticated;
alter table public.facilities add column workspace_id uuid references public.business_workspaces(id);
alter table public.organizations add column workspace_id uuid references public.business_workspaces(id);
alter table public.bookings add column team_id uuid references public.teams(id);
alter table public.bookings add column series_id uuid;
alter table public.bookings add constraint rink_booking_time_valid check(end_time>start_time) not valid;
alter table public.bookings add constraint rink_booking_amount_valid check(amount>=0) not valid;
-- Serialize writes on the actual area row: guards both confirmed and maintenance occupancy.
-- Exclusion constraint can be added in a later reviewed extension migration; this trigger
-- avoids requiring an unapproved extension for the first release.
create function rink_private.guard_booking() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.facility_areas a where a.id=new.area_id and a.facility_id=new.facility_id and a.is_active for update;
 if not found then raise exception 'Invalid or inactive ice area'; end if;
 if new.end_time<=new.start_time or new.amount<0 then raise exception 'Invalid booking time or amount'; end if;
 if new.team_id is not null and not exists(select 1 from public.teams t where t.id=new.team_id and t.organization_id=new.organization_id and t.is_active) then raise exception 'Team does not belong to organization'; end if;
 if new.status in ('confirmed','maintenance') and exists(select 1 from public.bookings b where b.area_id=new.area_id and b.id<>new.id and b.status in ('confirmed','maintenance') and b.start_time<new.end_time and b.end_time>new.start_time) then raise exception 'Ice is already reserved'; end if;
 return new;
end $$;
revoke all on function rink_private.guard_booking() from public,anon,authenticated;
create trigger rink_booking_integrity before insert or update on public.bookings for each row execute function rink_private.guard_booking();
create table public.facility_policies(facility_id uuid primary key references public.facilities(id),cancellation_notice_days integer check(cancellation_notice_days>=0),notice_basis text check(notice_basis in ('calendar_days','business_days')),policy_text text,updated_at timestamptz default now());
create table public.booking_cancellation_requests(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id),requested_by_person_id uuid not null references public.people(id),reason text not null check(length(reason) between 1 and 1000),status text not null default 'pending' check(status in ('pending','approved','denied','withdrawn')),requested_at timestamptz not null default now(),decided_by_person_id uuid references public.people(id),decided_at timestamptz,decision_note text,policy_snapshot jsonb);
create unique index rink_one_pending_cancel on public.booking_cancellation_requests(booking_id) where status='pending';
create table public.booking_financial_dispositions(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id),cancellation_request_id uuid unique references public.booking_cancellation_requests(id),status text not null default 'undetermined' check(status in ('undetermined','waived','owed_full','owed_partial','credited','offset_by_replacement')),amount numeric check(amount>=0),decided_by_person_id uuid references public.people(id),decided_at timestamptz,note text);
alter table public.open_slots add column is_public boolean not null default false;
alter table public.open_slots add column cancellation_request_id uuid unique references public.booking_cancellation_requests(id);
alter table public.open_slots add column released_by_person_id uuid references public.people(id);
alter table public.open_slots add column released_at timestamptz;
alter table public.open_slots add column awarded_booking_id uuid references public.bookings(id);
alter table public.open_slots drop constraint open_slots_status_check;
alter table public.open_slots add constraint open_slots_status_check check(status in ('open','claimed','expired','awarded','withdrawn'));
-- Both new-time requests and requests for released slots use this queue.
create table public.open_slot_requests(id uuid primary key default gen_random_uuid(),open_slot_id uuid references public.open_slots(id),facility_id uuid not null references public.facilities(id),area_id uuid not null references public.facility_areas(id),organization_id uuid not null references public.organizations(id),team_id uuid references public.teams(id),start_time timestamptz not null,end_time timestamptz not null,requested_by_person_id uuid not null references public.people(id),note text check(length(note)<=1000),status text not null default 'requested' check(status in ('requested','awarded','closed','withdrawn')),created_at timestamptz not null default now(),decided_at timestamptz,awarded_booking_id uuid references public.bookings(id),check(end_time>start_time));
create unique index rink_one_award on public.open_slot_requests(open_slot_id) where status='awarded';
create unique index rink_one_person_request on public.open_slot_requests(open_slot_id,requested_by_person_id) where status='requested' and open_slot_id is not null;
create table public.facility_waitlist(id uuid primary key default gen_random_uuid(),facility_id uuid not null references public.facilities(id),organization_id uuid not null references public.organizations(id),contact_person_id uuid not null references public.people(id),notify_opt_in boolean not null default false,active boolean not null default true,created_at timestamptz default now(),unique(facility_id,organization_id,contact_person_id));
-- First release: explicit interest in all openings at a chosen rink. Fine-grained
-- weekday/price/duration matching is deferred; no unsupported preferences are claimed.
create table public.open_slot_offers(id uuid primary key default gen_random_uuid(),open_slot_id uuid not null references public.open_slots(id),waitlist_id uuid references public.facility_waitlist(id),person_id uuid not null references public.people(id),channel text not null,status text not null check(status in ('queued','sent','failed','suppressed','no_channel')),created_at timestamptz default now(),unique(open_slot_id,person_id,channel));
-- No direct browser table access. All mutation/read shapes go through scoped RPCs.
alter table public.facility_policies enable row level security;
alter table public.booking_cancellation_requests enable row level security;
alter table public.booking_financial_dispositions enable row level security;
alter table public.open_slot_requests enable row level security;
alter table public.facility_waitlist enable row level security;
alter table public.open_slot_offers enable row level security;
alter table public.facility_policies force row level security;
alter table public.booking_cancellation_requests force row level security;
alter table public.booking_financial_dispositions force row level security;
alter table public.open_slot_requests force row level security;
alter table public.facility_waitlist force row level security;
alter table public.open_slot_offers force row level security;
revoke all on public.facility_policies,public.booking_cancellation_requests,public.booking_financial_dispositions,public.open_slot_requests,public.facility_waitlist,public.open_slot_offers from public,anon,authenticated;
commit;

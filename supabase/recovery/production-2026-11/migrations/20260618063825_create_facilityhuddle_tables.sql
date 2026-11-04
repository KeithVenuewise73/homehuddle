-- FacilityHuddle: facilities, areas, bookings, open slots, events
-- RLS intentionally left disabled for now, per project decision to enable
-- RLS across the whole ecosystem together before launch. Tables are built
-- with facility_id scoping throughout so policies can be added cleanly later.

create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique,
  facility_type text,
  address text,
  city text,
  state text,
  contact_email text,
  contact_phone text,
  access_code text not null,
  logo_url text,
  description text,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.facility_areas (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete cascade,
  name text not null,
  area_type text check (area_type in ('ice','field','court','room','training','other')) default 'other',
  color text default '#5B6B82',
  display_order integer default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete cascade,
  area_id uuid not null references public.facility_areas(id) on delete cascade,
  booking_type text check (booking_type in (
    'organization_rental','team_rental','coach_rental','private_rental',
    'birthday_party','tournament','camp','clinic','maintenance','open_skate'
  )) not null,
  title text,
  customer_name text,
  contact_email text,
  contact_phone text,
  organization_id uuid references public.organizations(id) on delete set null,
  coach_id uuid references public.coaches(id) on delete set null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  amount numeric default 0,
  status text check (status in ('confirmed','cancelled','maintenance')) default 'confirmed',
  is_recurring boolean default false,
  recurrence_rule text,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.open_slots (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete cascade,
  area_id uuid not null references public.facility_areas(id) on delete cascade,
  source_booking_id uuid references public.bookings(id) on delete set null,
  source text check (source in ('cancellation','unbooked')) not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  price numeric default 0,
  reason text,
  status text check (status in ('open','claimed','expired')) default 'open',
  claimed_by_name text,
  claimed_by_email text,
  claimed_by_phone text,
  views integer default 0,
  created_at timestamptz default now(),
  claimed_at timestamptz
);

create table public.facility_events (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete cascade,
  area_id uuid references public.facility_areas(id) on delete set null,
  event_type text check (event_type in ('tournament','camp','clinic','open_skate','tryout','fundraiser')) not null,
  title text not null,
  description text,
  start_time timestamptz not null,
  end_time timestamptz,
  capacity integer,
  enrolled integer default 0,
  price numeric default 0,
  status text check (status in ('active','cancelled','completed')) default 'active',
  created_at timestamptz default now()
);

create index idx_facility_areas_facility on public.facility_areas(facility_id);
create index idx_bookings_facility on public.bookings(facility_id);
create index idx_bookings_area on public.bookings(area_id);
create index idx_bookings_start_time on public.bookings(start_time);
create index idx_open_slots_facility on public.open_slots(facility_id);
create index idx_open_slots_status on public.open_slots(status);
create index idx_facility_events_facility on public.facility_events(facility_id);
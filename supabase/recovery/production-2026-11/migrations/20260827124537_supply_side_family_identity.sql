alter table public.open_slots
  add column if not exists claimed_by_family_id uuid references public.families(id) on delete set null;

alter table public.bookings
  add column if not exists family_id uuid references public.families(id) on delete set null;

alter table public.clinic_registrations
  add column if not exists family_id uuid references public.families(id) on delete set null;

create index if not exists open_slots_claimed_family_idx   on public.open_slots(claimed_by_family_id);
create index if not exists bookings_family_idx             on public.bookings(family_id);
create index if not exists clinic_registrations_family_idx on public.clinic_registrations(family_id);

comment on column public.open_slots.claimed_by_family_id is
  'Resolves a claim to a household so the booking can reach every member. NULL means an unrecognized walk-up; claimed_by_* text columns still apply.';
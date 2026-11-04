-- Who bought it, as distinct from which family it covers.
-- Nullable + defaulted so existing rows and the live Stripe webhook are unaffected.
alter table public.subscriptions
  add column if not exists payer_person_id uuid references public.people(id),
  add column if not exists payer_role text not null default 'parent'
    check (payer_role in ('parent','grandparent','other')),
  add column if not exists is_gift boolean not null default false,
  add column if not exists billing_interval text not null default 'month'
    check (billing_interval in ('month','year'));

create index if not exists subscriptions_payer_idx
  on public.subscriptions (payer_person_id) where payer_person_id is not null;

-- One purchaser covering several households: bill per family, but keep them
-- linked so the portal, dunning, and churn outreach reach the right person.
create or replace view public.gifted_subscriptions as
select
  p.id            as payer_person_id,
  p.display_name  as payer_name,
  p.phone         as payer_phone,
  count(*)                                  as families_covered,
  sum(case when s.status in ('active','trialing') then 1 else 0 end) as active_covered,
  string_agg(f.family_name, ', ' order by f.family_name)             as families
from public.subscriptions s
join public.people   p on p.id = s.payer_person_id
join public.families f on f.id = s.family_id
where s.is_gift
group by p.id, p.display_name, p.phone
order by families_covered desc;

comment on view public.gifted_subscriptions is
  'Grandparent/third-party purchasers and every household they cover. One row per payer.';
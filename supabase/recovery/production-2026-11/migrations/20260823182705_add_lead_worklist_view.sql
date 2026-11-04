-- Single worklist for follow-up: everything about a lead, prioritized by staleness.
create or replace view public.lead_worklist as
select
  l.id,
  l.status,
  extract(day from now() - l.created_at)::int as days_cold,
  l.name,
  l.organization_name,
  l.role,
  l.platform_interest,
  l.phone,
  l.email,
  l.message,
  l.source_page,
  l.source_platform,
  l.created_at,
  case
    when l.platform_interest in ('FacilityHuddle','OrganizationHuddle','TournamentHuddle') then 'B2B'
    else 'consumer'
  end as segment
from public.leads l
order by
  case when l.status = 'new' then 0 else 1 end,
  l.created_at asc;

comment on view public.lead_worklist is
  'Follow-up worklist. Unworked leads first, oldest first. B2B segment = revenue priority.';
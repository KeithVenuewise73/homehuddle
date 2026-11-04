-- One row per creative cut: reach -> signup -> trial -> paid.
create or replace view public.creative_funnel as
with human_traffic as (
  select utm_campaign, utm_content, session_id
  from public.page_views
  where utm_content is not null
    and user_agent not ilike '%bot%' and user_agent not ilike '%crawl%'
    and user_agent not ilike '%spider%' and user_agent not ilike '%headless%'
),
reach as (
  select utm_campaign, utm_content, count(distinct session_id) sessions
  from human_traffic group by 1,2
),
conv as (
  select utm_campaign, utm_content,
         count(*) signups,
         count(trial_started_at) trials,
         count(converted_at) paid
  from public.signup_attribution
  where utm_content is not null
  group by 1,2
)
select
  coalesce(r.utm_campaign, c.utm_campaign) as campaign,
  coalesce(r.utm_content,  c.utm_content)  as creative,
  cr.pain_moment,
  cr.aspect_ratio,
  coalesce(r.sessions,0) sessions,
  coalesce(c.signups,0)  signups,
  coalesce(c.trials,0)   trials,
  coalesce(c.paid,0)     paid,
  round(100.0 * coalesce(c.signups,0) / nullif(r.sessions,0), 1) as signup_rate_pct,
  round(100.0 * coalesce(c.paid,0)    / nullif(c.trials,0),  1) as trial_to_paid_pct
from reach r
full outer join conv c
  on r.utm_campaign is not distinct from c.utm_campaign
 and r.utm_content  is not distinct from c.utm_content
left join public.ad_creatives cr
  on cr.slug = coalesce(r.utm_content, c.utm_content)
order by sessions desc nulls last;

comment on view public.creative_funnel is
  'Per-creative funnel. Bots excluded. Read this at 72h to decide what earns paid spend.';
create or replace view public.creative_funnel as
with human_traffic as (
  select coalesce(utm_campaign,'(none)') camp, utm_content, session_id
  from public.page_views
  where utm_content is not null
    and user_agent not ilike '%bot%' and user_agent not ilike '%crawl%'
    and user_agent not ilike '%spider%' and user_agent not ilike '%headless%'
),
reach as (
  select camp, utm_content, count(distinct session_id) sessions
  from human_traffic group by 1,2
),
conv as (
  select coalesce(utm_campaign,'(none)') camp, utm_content,
         count(*) signups, count(trial_started_at) trials, count(converted_at) paid
  from public.signup_attribution
  where utm_content is not null
  group by 1,2
),
keys as (
  select camp, utm_content from reach
  union
  select camp, utm_content from conv
)
select
  k.camp as campaign,
  k.utm_content as creative,
  cr.pain_moment,
  cr.aspect_ratio,
  coalesce(r.sessions,0) sessions,
  coalesce(c.signups,0)  signups,
  coalesce(c.trials,0)   trials,
  coalesce(c.paid,0)     paid,
  round(100.0 * coalesce(c.signups,0) / nullif(r.sessions,0), 1) as signup_rate_pct,
  round(100.0 * coalesce(c.paid,0)    / nullif(c.trials,0),  1) as trial_to_paid_pct
from keys k
left join reach r on r.camp = k.camp and r.utm_content = k.utm_content
left join conv  c on c.camp = k.camp and c.utm_content = k.utm_content
left join public.ad_creatives cr on cr.slug = k.utm_content
order by sessions desc nulls last;
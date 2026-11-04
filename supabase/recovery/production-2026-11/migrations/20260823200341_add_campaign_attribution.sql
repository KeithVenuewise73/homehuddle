-- UTM capture on the existing tracking table.
alter table public.page_views add column if not exists utm_source   text;
alter table public.page_views add column if not exists utm_medium   text;
alter table public.page_views add column if not exists utm_campaign text;
alter table public.page_views add column if not exists utm_content  text;  -- the creative cut
alter table public.page_views add column if not exists utm_term     text;
alter table public.page_views add column if not exists landing_page text;

create index if not exists page_views_utm_idx
  on public.page_views (utm_campaign, utm_content, viewed_at desc);

-- Registry of creative cuts, so utm_content is a controlled vocabulary
-- instead of free text you can't group on later.
create table if not exists public.ad_creatives (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,          -- goes in utm_content
  concept text not null,              -- 'morning_chaos'
  pain_moment text not null,          -- the hypothesis under test
  aspect_ratio text not null,         -- 9:16, 4:5, 16:9
  duration_sec integer,
  version text default 'v0.9',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.ad_creatives enable row level security;
create policy anon_read_creatives on public.ad_creatives for select to anon using (true);

-- First-touch attribution, captured at signup and never overwritten.
create table if not exists public.signup_attribution (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families(id) on delete cascade,
  person_id uuid,
  session_id text,
  utm_source text, utm_medium text, utm_campaign text, utm_content text,
  referrer text,
  landing_page text,
  signed_up_at timestamptz not null default now(),
  trial_started_at timestamptz,
  converted_at timestamptz,
  is_founder boolean not null default false
);
alter table public.signup_attribution enable row level security;
create unique index if not exists signup_attr_family_uniq
  on public.signup_attribution (family_id) where family_id is not null;
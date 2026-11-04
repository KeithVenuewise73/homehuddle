-- 1. additive columns
alter table public.platform_status
  add column if not exists feed_id uuid references public.feeds(id),
  add column if not exists last_success timestamptz;

-- 2. clear legacy null-feed_id rows (Option A) — stale monitoring-only data
delete from public.platform_status where feed_id is null;

-- 3. switch grain: drop (platform,kid) PK, key on feed_id instead
alter table public.platform_status drop constraint platform_status_pkey;
alter table public.platform_status add constraint platform_status_feed_id_key unique (feed_id);
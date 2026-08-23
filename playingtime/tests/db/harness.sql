-- ============================================================================
-- Supabase preconditions, stubbed, so 0001_playingtime.sql can be applied to a
-- bare Postgres and verified before it ever goes near a real project.
--
-- This file is NOT part of the migration. It stands in for what Supabase already
-- provides: the auth schema, auth.users, auth.uid(), and the anon/authenticated
-- roles. Keeping it separate is the point — the migration must not depend on
-- anything that is not already true of the target project.
-- ============================================================================

create schema if not exists auth;

create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text,
  raw_user_meta_data  jsonb default '{}'::jsonb
);

-- Supabase resolves auth.uid() from the request JWT. Here it reads a GUC that
-- the tests set, which is exactly how a policy sees it at runtime.
create or replace function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;

grant usage on schema auth to authenticated, anon;

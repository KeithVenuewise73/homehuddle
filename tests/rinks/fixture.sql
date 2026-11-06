-- Synthetic structural fixture only: no production data or credentials.
create role anon; create role authenticated;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
create table people(id uuid primary key default gen_random_uuid(),auth_user_id uuid,display_name text);
create table business_workspaces(id uuid primary key default gen_random_uuid());
create table workspace_members(workspace_id uuid,person_id uuid,status text);
create table workspace_roles(workspace_id uuid,person_id uuid,role text);
create table organizations(id uuid primary key default gen_random_uuid(),name text);
create table teams(id uuid primary key default gen_random_uuid(),organization_id uuid,name text,is_active boolean default true);
create table facilities(id uuid primary key default gen_random_uuid(),name text,slug text,address text,is_active boolean default true);
create table facility_areas(id uuid primary key default gen_random_uuid(),facility_id uuid,name text,area_type text,is_active boolean default true);
create table bookings(id uuid primary key default gen_random_uuid(),facility_id uuid,area_id uuid,booking_type text,title text,organization_id uuid,coach_id uuid,start_time timestamptz,end_time timestamptz,amount numeric default 0,status text default 'confirmed',updated_at timestamptz default now());
create table open_slots(id uuid primary key default gen_random_uuid(),facility_id uuid,area_id uuid,source_booking_id uuid,source text,start_time timestamptz,end_time timestamptz,price numeric,status text default 'open',constraint open_slots_status_check check(status in ('open','claimed','expired')));
create table calendar_events(id uuid primary key default gen_random_uuid(),source_module text,source_table text,source_id text,title text,start_time timestamptz,end_time timestamptz,event_type text,location_name text,location_address text,organization_id uuid,facility_id uuid,is_public boolean,status text check(status in ('active','cancelled','completed')),updated_at timestamptz default now(),unique(source_module,source_table,source_id));
create function current_person_id() returns uuid language sql stable security definer set search_path=public as $$select id from public.people where auth_user_id=auth.uid() limit 1$$;

-- ============================================================================
-- 0004 · In-app account deletion (Apple 5.1.1(v))  — owner-scoped, safe
-- ----------------------------------------------------------------------------
-- Phase 7. Requirements honored:
--   • authenticated only, and ONLY the family OWNER may delete (a non-owner
--     member cannot destroy shared family data they don't own)
--   • deliberate: caller confirms in the UI; this records the request
--   • not instantaneous: soft-delete now + 7-day grace, then a service-role job
--     hard-deletes (so accidental deletions are recoverable within the window)
--   • billing/accounting records are preserved (subscriptions rows are retained,
--     just marked; Stripe/Apple cancellation is handled by the delete-account
--     Edge Function, not here)
--
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

-- Soft-delete + schedule columns on families (additive) ----------------------
alter table public.families
  add column if not exists deletion_requested_at  timestamptz,
  add column if not exists deletion_scheduled_for timestamptz,
  add column if not exists deleted_at             timestamptz;

create table if not exists public.account_deletion_requests (
  id             uuid primary key default gen_random_uuid(),
  family_id      uuid not null references public.families(id) on delete cascade,
  requested_by   uuid,               -- family_members.id of the owner
  requested_at   timestamptz not null default now(),
  scheduled_for  timestamptz not null,
  status         text not null default 'scheduled'
                 check (status in ('scheduled','cancelled','completed')),
  reason         text
);
alter table public.account_deletion_requests enable row level security;

drop policy if exists adr_select_own on public.account_deletion_requests;
create policy adr_select_own on public.account_deletion_requests
  for select to authenticated
  using (family_id in (select current_family_ids(false)));

drop policy if exists adr_service_all on public.account_deletion_requests;
create policy adr_service_all on public.account_deletion_requests
  for all to service_role using (true) with check (true);

-- ── Owner-scoped request function ───────────────────────────────────────────
-- Marks the family for deletion after a grace window. Raises if the caller is
-- not the OWNER of the family, preventing deletion of shared data by a member.
create or replace function public.request_account_deletion(
  p_family_id uuid,
  p_reason    text default null,
  p_grace_days integer default 7
) returns public.account_deletion_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_person uuid := public.current_person_id();
  v_owner  uuid;
  v_req    public.account_deletion_requests;
begin
  if v_person is null then
    raise exception 'not authenticated';
  end if;

  -- Caller must be the OWNER member of this family.
  select fm.id into v_owner
    from public.family_members fm
   where fm.family_id = p_family_id
     and fm.is_owner = true
     and fm.person_id = v_person
   limit 1;

  if v_owner is null then
    raise exception 'only the family owner may delete this account';
  end if;

  -- Soft-delete now; schedule hard delete after the grace window.
  update public.families
     set deletion_requested_at  = now(),
         deletion_scheduled_for = now() + make_interval(days => p_grace_days),
         status                 = 'deletion_pending'
   where id = p_family_id;

  -- Stop future notifications immediately.
  update public.feeds set is_active = false where email in (select current_family_emails());

  insert into public.account_deletion_requests (family_id, requested_by, scheduled_for, reason)
  values (p_family_id, v_owner, now() + make_interval(days => p_grace_days), p_reason)
  returning * into v_req;

  return v_req;
end;
$$;

revoke all on function public.request_account_deletion(uuid, text, integer) from public, anon;
grant execute on function public.request_account_deletion(uuid, text, integer) to authenticated;

-- Allow a user to CANCEL a pending deletion during the grace window (owner only).
create or replace function public.cancel_account_deletion(p_family_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_person uuid := public.current_person_id();
begin
  if not exists (select 1 from public.family_members
                 where family_id = p_family_id and is_owner and person_id = v_person) then
    raise exception 'only the family owner may cancel deletion';
  end if;
  update public.families
     set deletion_requested_at = null, deletion_scheduled_for = null, status = 'active'
   where id = p_family_id;
  update public.account_deletion_requests
     set status = 'cancelled'
   where family_id = p_family_id and status = 'scheduled';
end;
$$;
revoke all on function public.cancel_account_deletion(uuid) from public, anon;
grant execute on function public.cancel_account_deletion(uuid) to authenticated;

commit;

-- The actual hard delete (after grace) is performed by the `delete-account`
-- Edge Function running as service_role (cancels Stripe/Apple, then deletes
-- family + cascaded children), so relational + billing consequences are handled
-- deliberately rather than by a blind `DELETE FROM families`.
--
-- ROLLBACK (reference):
--   drop function if exists public.cancel_account_deletion(uuid);
--   drop function if exists public.request_account_deletion(uuid, text, integer);
--   drop table if exists public.account_deletion_requests;
--   alter table public.families
--     drop column if exists deletion_requested_at,
--     drop column if exists deletion_scheduled_for,
--     drop column if exists deleted_at;

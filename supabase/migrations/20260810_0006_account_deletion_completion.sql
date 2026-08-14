-- ============================================================================
-- 0006 · Account deletion completion  (CEO-validation fix V5)
-- ----------------------------------------------------------------------------
-- Adds (a) a NON-OWNER self-removal path (a member can delete their own
-- identity without destroying shared family data), and (b) a hard-delete job
-- so scheduled deletions ACTUALLY complete after the grace window — PII is
-- purged/anonymized while a minimal billing ledger is retained.
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

-- ── Non-owner: delete only your OWN membership/identity ─────────────────────
create or replace function public.delete_my_membership()
returns text
language plpgsql security definer set search_path = public as $$
declare v_person uuid := public.current_person_id();
declare v_rows int;
begin
  if v_person is null then raise exception 'not authenticated'; end if;

  -- An OWNER cannot use this path (that would orphan shared data) — they must
  -- use request_account_deletion (whole-family, owner-scoped, with grace).
  if exists (select 1 from public.family_members
             where person_id = v_person and is_owner = true) then
    raise exception 'owners must delete the whole account, not just their membership';
  end if;

  delete from public.family_members where person_id = v_person;
  get diagnostics v_rows = row_count;
  return 'removed ' || v_rows || ' membership(s)';
end; $$;
revoke all on function public.delete_my_membership() from public, anon;
grant execute on function public.delete_my_membership() to authenticated;

-- ── Per-family PG purge (idempotent) — called by the hard-delete Edge worker ─
-- AFTER it has completed the external-provider cleanups (Stripe/RevenueCat/auth).
-- Anonymizes family PII and purges child/member data; keeps a minimal billing
-- ledger (subscriptions rows hold provider ids/amounts, not names). Safe to run
-- twice: an already-deleted family (deleted_at set) is a no-op.
create or replace function public.hard_delete_family(p_family_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_due boolean;
begin
  select (deletion_scheduled_for is not null and deletion_scheduled_for <= now() and deleted_at is null)
    into v_due from public.families where id = p_family_id;
  if v_due is null then return false; end if;   -- unknown family
  if v_due is not true then return false; end if; -- not due, or already deleted (idempotent)

  delete from public.family_members where family_id = p_family_id;
  delete from public.feeds where email in (select email from public.families where id = p_family_id);
  delete from public.device_tokens where family_id = p_family_id;
  delete from public.push_subscriptions where family_id = p_family_id;

  update public.family_product_entitlements set is_active = false, updated_at = now()
    where family_id = p_family_id;

  -- phone & pin are NOT NULL in the live schema → redact to non-null placeholders.
  update public.families
     set family_name = 'deleted', email = 'deleted+' || p_family_id || '@example.invalid',
         phone = 'deleted', pin = 'deleted', deleted_at = now(), status = 'deleted'
   where id = p_family_id;

  update public.account_deletion_requests set status = 'completed'
    where family_id = p_family_id and status = 'scheduled';
  return true;
end; $$;
revoke all on function public.hard_delete_family(uuid) from public, anon, authenticated;
grant execute on function public.hard_delete_family(uuid) to service_role;

-- Convenience: list families whose grace has expired (worker reads this).
create or replace function public.due_for_deletion()
returns table(family_id uuid, scheduled_for timestamptz)
language sql security definer set search_path = public as $$
  select id, deletion_scheduled_for from public.families
  where deletion_scheduled_for is not null and deletion_scheduled_for <= now() and deleted_at is null
  order by deletion_scheduled_for asc;
$$;
revoke all on function public.due_for_deletion() from public, anon, authenticated;
grant execute on function public.due_for_deletion() to service_role;

-- Pure-DB fallback (no external coordination) — loops hard_delete_family.
create or replace function public.hard_delete_due_accounts()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select family_id from public.due_for_deletion() loop
    if public.hard_delete_family(r.family_id) then n := n + 1; end if;
  end loop;
  return n;
end; $$;
revoke all on function public.hard_delete_due_accounts() from public, anon, authenticated;
grant execute on function public.hard_delete_due_accounts() to service_role;

commit;

-- Scheduling (ops, NOT applied here): run hard_delete_due_accounts() daily, e.g.
--   select cron.schedule('hard-delete-accounts','0 3 * * *',
--     $$ select public.hard_delete_due_accounts() $$);
-- (requires pg_cron) OR a daily invocation of the delete-account Edge job that
-- also deletes the Supabase auth user and the Stripe/RevenueCat customer.
--
-- ROLLBACK (reference):
--   drop function if exists public.hard_delete_due_accounts();
--   drop function if exists public.delete_my_membership();

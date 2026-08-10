-- ============================================================================
-- 0005 · Admin read access for the ops dashboard  (Phase 10, ADDITIVE)
-- ----------------------------------------------------------------------------
-- The existing dashboard fetched with the ANON key + a client-side PIN. RLS
-- (correctly) denies anon reads of family data, so those reads returned nothing
-- AND the PIN was cosmetic. This migration gives a REAL, server-verified admin
-- (public.is_admin()) scoped read access, and a single aggregate metrics RPC so
-- the dashboard shows verified subscription numbers without exposing raw PII
-- broadly.
--
-- Admin identity is whatever is_admin() already encodes (admin_users table).
-- ⚠️ REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- ============================================================================

begin;

-- Scoped admin SELECT policies (added ALONGSIDE existing own-family policies) --
drop policy if exists families_admin_select on public.families;
create policy families_admin_select on public.families
  for select to authenticated using (public.is_admin());

drop policy if exists subscriptions_admin_select on public.subscriptions;
create policy subscriptions_admin_select on public.subscriptions
  for select to authenticated using (public.is_admin());

drop policy if exists feeds_admin_select on public.feeds;
create policy feeds_admin_select on public.feeds
  for select to authenticated using (public.is_admin());

drop policy if exists family_members_admin_select on public.family_members;
create policy family_members_admin_select on public.family_members
  for select to authenticated using (public.is_admin());

drop policy if exists adr_admin_select on public.account_deletion_requests;
create policy adr_admin_select on public.account_deletion_requests
  for select to authenticated using (public.is_admin());

-- ── Aggregate metrics RPC (verified counts, no row-level PII) ────────────────
create or replace function public.admin_dashboard_metrics()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then
    raise exception 'not authorized';
  end if;

  select json_build_object(
    'families_total',       (select count(*) from families),
    'families_active',      (select count(*) from families where status not in ('cancelled','deletion_pending','deleted')),
    'families_deleting',    (select count(*) from families where status = 'deletion_pending'),
    'subs_founder',         (select count(*) from subscriptions where product='homehuddle' and founder),
    'subs_standard',        (select count(*) from subscriptions where product='homehuddle' and not founder),
    'subs_trialing',        (select count(*) from subscriptions where status='trialing'),
    'subs_active',          (select count(*) from subscriptions where status='active'),
    'subs_past_due',        (select count(*) from subscriptions where status='past_due'),
    'subs_canceled',        (select count(*) from subscriptions where status='canceled'),
    'subs_by_source',       (select coalesce(json_object_agg(source, c),'{}'::json)
                               from (select source, count(*) c from subscriptions group by source) t),
    'founder_slots_remaining', public.founder_slots_remaining('homehuddle'),
    'feeds_active',         (select count(*) from feeds where is_active and coalesce(status,'') <> 'cancelled'),
    'errors_24h',           (select count(*) from client_errors where created_at > now() - interval '24 hours'),
    'errors_by_kind_24h',   (select coalesce(json_object_agg(kind, c),'{}'::json)
                               from (select kind, count(*) c from client_errors
                                     where created_at > now() - interval '24 hours' group by kind) t),
    'generated_at',         now()
  ) into result;

  return result;
end;
$$;

revoke all on function public.admin_dashboard_metrics() from public, anon;
grant execute on function public.admin_dashboard_metrics() to authenticated;

commit;

-- ROLLBACK (reference):
--   drop function if exists public.admin_dashboard_metrics();
--   drop policy if exists families_admin_select on public.families;
--   drop policy if exists subscriptions_admin_select on public.subscriptions;
--   drop policy if exists feeds_admin_select on public.feeds;
--   drop policy if exists family_members_admin_select on public.family_members;
--   drop policy if exists adr_admin_select on public.account_deletion_requests;

\set ON_ERROR_STOP on
\pset pager off

-- Helper: make a family with an owner person.
create or replace function tst_make_family(p_id uuid, p_person uuid, p_email text) returns void
language plpgsql as $$
begin
  insert into public.families(id, family_name, email, phone, pin, status)
    values (p_id, 'Fam '||left(p_id::text,8), p_email, '+1555'||floor(random()*1e7)::text, '0000', 'active')
    on conflict (id) do nothing;
  insert into public.family_members(family_id, name, is_owner, person_id, role)
    values (p_id, 'Owner', true, p_person, 'parent') on conflict do nothing;
end $$;

\echo '==================== PHASE 8: SOURCE COEXISTENCE ===================='
select tst_make_family('aaaaaaaa-0000-4000-a000-000000000001','11111111-0000-4000-a000-000000000001','x@demo.invalid');

-- 1) Active Stripe HomeHuddle
insert into public.subscriptions(family_id, product, source, status, current_period_end, stripe_customer_id, founder)
 values ('aaaaaaaa-0000-4000-a000-000000000001','homehuddle','stripe','active', now()+interval '30 days','cus_x', false)
 on conflict (family_id,product,source) do update set status='active';
select recompute_entitlement('aaaaaaaa-0000-4000-a000-000000000001','homehuddle');

-- 2) Add Apple source (must NOT overwrite Stripe)
insert into public.subscriptions(family_id, product, source, status, current_period_end, founder)
 values ('aaaaaaaa-0000-4000-a000-000000000001','homehuddle','apple','active', now()+interval '30 days', false)
 on conflict (family_id,product,source) do update set status='active';
select recompute_entitlement('aaaaaaaa-0000-4000-a000-000000000001','homehuddle');

do $$
declare n int; act boolean;
begin
  select count(*) into n from subscriptions where family_id='aaaaaaaa-0000-4000-a000-000000000001' and product='homehuddle';
  if n <> 2 then raise exception 'COEXIST FAIL: expected 2 purchase rows, got %', n; end if;
  select is_active into act from family_product_entitlements where family_id='aaaaaaaa-0000-4000-a000-000000000001';
  if not act then raise exception 'COEXIST FAIL: entitlement not active with both sources'; end if;
  raise notice 'OK  both sources coexist (2 rows), entitlement active';
end $$;

-- 3) Expire Apple → still active via Stripe
update subscriptions set status='canceled', current_period_end=now()-interval '1 day'
 where family_id='aaaaaaaa-0000-4000-a000-000000000001' and source='apple';
select recompute_entitlement('aaaaaaaa-0000-4000-a000-000000000001','homehuddle');
do $$ declare act boolean; src text;
begin
  select is_active, active_source into act, src from family_product_entitlements where family_id='aaaaaaaa-0000-4000-a000-000000000001';
  if not act then raise exception 'FAIL: should remain active via Stripe'; end if;
  if src <> 'stripe' then raise exception 'FAIL: active_source should be stripe, got %', src; end if;
  raise notice 'OK  Apple expired → still active via Stripe (source=%)', src;
end $$;

-- 4) Expire Stripe → inactive
update subscriptions set status='canceled', current_period_end=now()-interval '1 day'
 where family_id='aaaaaaaa-0000-4000-a000-000000000001' and source='stripe';
select recompute_entitlement('aaaaaaaa-0000-4000-a000-000000000001','homehuddle');
do $$ declare act boolean;
begin
  select is_active into act from family_product_entitlements where family_id='aaaaaaaa-0000-4000-a000-000000000001';
  if act then raise exception 'FAIL: should be inactive after both expire'; end if;
  raise notice 'OK  both expired → entitlement inactive';
end $$;

\echo '==================== PHASE 7: FOUNDER LIFECYCLE ===================='
-- Fill exactly 100 reservations across distinct families; 101st must fail.
do $$
declare i int; fid uuid; ok boolean; nfail int := 0;
begin
  for i in 1..101 loop
    fid := ('bbbbbbbb-0000-4000-a000-'||lpad(i::text,12,'0'))::uuid;
    perform tst_make_family(fid, ('cccccccc-0000-4000-a000-'||lpad(i::text,12,'0'))::uuid, 'f'||i||'@demo.invalid');
    ok := reserve_founder_slot(fid,'homehuddle','apple','ref'||i);
    if i <= 100 and not ok then raise exception 'FAIL: reserve #% should succeed', i; end if;
    if i = 101 and ok then raise exception 'FAIL: reserve #101 MUST fail (cap=100)'; end if;
    if not ok then nfail := nfail + 1; end if;
  end loop;
  raise notice 'OK  100 reserved, #101 refused. remaining=%', founder_slots_remaining('homehuddle');
end $$;

-- Non-converting reservation released → frees a slot → new family can reserve.
select release_founder_slot('bbbbbbbb-0000-4000-a000-000000000050','homehuddle') as release_50;
do $$ declare ok boolean;
begin
  if founder_slots_remaining('homehuddle') <> 1 then raise exception 'FAIL: releasing a reservation should free 1 slot'; end if;
  perform tst_make_family('dddddddd-0000-4000-a000-000000000001','eeee1111-0000-4000-a000-000000000001','new@demo.invalid');
  ok := reserve_founder_slot('dddddddd-0000-4000-a000-000000000001','homehuddle','stripe','newref');
  if not ok then raise exception 'FAIL: new family should reserve the freed slot'; end if;
  if founder_slots_remaining('homehuddle') <> 0 then raise exception 'FAIL: should be full again'; end if;
  raise notice 'OK  released reservation freed a slot; next candidate reserved it';
end $$;

-- Grant (first paid) then lapse: slot is PERMANENT, never re-pooled.
select grant_founder_slot('bbbbbbbb-0000-4000-a000-000000000001','homehuddle','apple','ref1') as grant_1;
select release_founder_slot('bbbbbbbb-0000-4000-a000-000000000001','homehuddle') as lapse_granted;
do $$ declare st text; rem int;
begin
  select state into st from founder_grants where family_id='bbbbbbbb-0000-4000-a000-000000000001';
  rem := founder_slots_remaining('homehuddle');
  if st <> 'granted' then raise exception 'FAIL: granted founder must STAY granted after lapse, got %', st; end if;
  if rem <> 0 then raise exception 'FAIL: granted slot must NOT be re-pooled; remaining=%', rem; end if;
  raise notice 'OK  granted founder lapsed → state still granted, slot NOT returned (remaining=0). #101 impossible';
end $$;

\echo '==================== PHASE 9: ACCOUNT DELETION ===================='
select tst_make_family('ffffffff-0000-4000-a000-000000000001','99999999-0000-4000-a000-000000000001','owner@demo.invalid');
insert into public.family_members(family_id, name, is_owner, person_id, role)
  values ('ffffffff-0000-4000-a000-000000000001','Kid', false, '99999999-0000-4000-a000-000000000002','child');
insert into public.feeds(email, kid_name, platform, ical_url, is_active)
  values ('owner@demo.invalid','Kid','demo','http://x', true);

-- Non-owner tries whole-family delete → blocked; can remove only own membership.
select set_config('test.person_id','99999999-0000-4000-a000-000000000002', false);
do $$ begin
  begin
    perform request_account_deletion('ffffffff-0000-4000-a000-000000000001', null, 7);
    raise exception 'FAIL: non-owner should NOT delete whole family';
  exception when others then
    if sqlerrm like '%owner%' then raise notice 'OK  non-owner blocked from whole-family deletion'; else raise; end if;
  end;
end $$;
select delete_my_membership() as nonowner_self_remove;
do $$ declare n int;
begin
  select count(*) into n from family_members where person_id='99999999-0000-4000-a000-000000000002';
  if n <> 0 then raise exception 'FAIL: non-owner membership not removed'; end if;
  select count(*) into n from family_members where family_id='ffffffff-0000-4000-a000-000000000001';
  if n < 1 then raise exception 'FAIL: shared family data destroyed by non-owner!'; end if;
  raise notice 'OK  non-owner removed only own membership; family intact';
end $$;

-- Owner requests deletion → pending + feeds disabled; then cancel restores.
select set_config('test.person_id','99999999-0000-4000-a000-000000000001', false);
select scheduled_for is not null as scheduled from request_account_deletion('ffffffff-0000-4000-a000-000000000001','bye',7);
do $$ declare st text; feed_active boolean;
begin
  select status into st from families where id='ffffffff-0000-4000-a000-000000000001';
  select bool_or(is_active) into feed_active from feeds where email='owner@demo.invalid';
  if st <> 'deletion_pending' then raise exception 'FAIL: family not deletion_pending'; end if;
  if feed_active then raise exception 'FAIL: feeds not disabled on deletion request'; end if;
  raise notice 'OK  owner deletion scheduled; status=deletion_pending; feeds disabled';
end $$;
select cancel_account_deletion('ffffffff-0000-4000-a000-000000000001');
do $$ declare st text;
begin
  select status into st from families where id='ffffffff-0000-4000-a000-000000000001';
  if st <> 'active' then raise exception 'FAIL: cancel did not restore (status=%)', st; end if;
  raise notice 'OK  deletion cancelled during grace → restored to active';
end $$;

-- Expired grace → hard delete; idempotent second run.
select request_account_deletion('ffffffff-0000-4000-a000-000000000001','final',7);
update families set deletion_scheduled_for = now() - interval '1 day' where id='ffffffff-0000-4000-a000-000000000001';
select hard_delete_family('ffffffff-0000-4000-a000-000000000001') as purge1;
select hard_delete_family('ffffffff-0000-4000-a000-000000000001') as purge2_idempotent;
do $$ declare fn text; nm int; act boolean; rq text;
begin
  select family_name into fn from families where id='ffffffff-0000-4000-a000-000000000001';
  select count(*) into nm from family_members where family_id='ffffffff-0000-4000-a000-000000000001';
  select is_active into act from family_product_entitlements where family_id='ffffffff-0000-4000-a000-000000000001';
  select status into rq from account_deletion_requests where family_id='ffffffff-0000-4000-a000-000000000001' order by requested_at desc limit 1;
  if fn <> 'deleted' then raise exception 'FAIL: family not anonymized (%)', fn; end if;
  if nm <> 0 then raise exception 'FAIL: members not purged'; end if;
  if coalesce(act,false) then raise exception 'FAIL: entitlement not deactivated'; end if;
  if rq <> 'completed' then raise exception 'FAIL: deletion request not completed'; end if;
  raise notice 'OK  hard delete: PII anonymized, members purged, entitlement off, request completed, 2nd run idempotent';
end $$;

\echo '==================== PHASE 10: ADMIN METRICS ===================='
select set_config('test.is_admin','true', false);
select json_pretty(admin_dashboard_metrics()) as admin_metrics;

\echo '==================== ALL ASSERTIONS PASSED ===================='

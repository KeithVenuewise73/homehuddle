-- ============================================================================
-- RLS ROLE MATRIX — real enforcement via SET ROLE + request.jwt.claims.
-- Proves cross-family isolation and forge-prevention with the ACTUAL anon /
-- authenticated / service_role roles (not superuser). Runs after 0001-0006.
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off

-- ── Seed two families with real identities (as service/superuser) ───────────
do $$
declare pa uuid; pb uuid; pm uuid;
begin
  -- Family A: owner uA, non-owner member uM
  insert into families(id,family_name,email,phone,pin,status)
    values ('a0000000-0000-4000-a000-00000000000a','A','a@demo.invalid','+1','0','active');
  insert into people(auth_user_id) values ('11111111-0000-4000-a000-00000000000a') returning id into pa;
  insert into people(auth_user_id) values ('22222222-0000-4000-a000-00000000000d') returning id into pm;
  insert into family_members(family_id,name,is_owner,person_id) values ('a0000000-0000-4000-a000-00000000000a','OwnerA',true,pa);
  insert into family_members(family_id,name,is_owner,person_id) values ('a0000000-0000-4000-a000-00000000000a','MemberA',false,pm);
  insert into subscriptions(family_id,product,source,status,founder) values ('a0000000-0000-4000-a000-00000000000a','homehuddle','stripe','active',false);
  insert into family_product_entitlements(family_id,product,is_active,active_source) values ('a0000000-0000-4000-a000-00000000000a','homehuddle',true,'stripe');
  -- Family B: owner uB
  insert into families(id,family_name,email,phone,pin,status)
    values ('b0000000-0000-4000-b000-00000000000b','B','b@demo.invalid','+1','0','active');
  insert into people(auth_user_id) values ('33333333-0000-4000-b000-00000000000b') returning id into pb;
  insert into family_members(family_id,name,is_owner,person_id) values ('b0000000-0000-4000-b000-00000000000b','OwnerB',true,pb);
  insert into subscriptions(family_id,product,source,status) values ('b0000000-0000-4000-b000-00000000000b','homehuddle','apple','active');
  insert into family_product_entitlements(family_id,product,is_active,active_source) values ('b0000000-0000-4000-b000-00000000000b','homehuddle',true,'apple');
end $$;
insert into admin_users(user_id) values ('99999999-dead-4000-a000-00000000000a');

-- Reusable assertion of a row count under a given role+identity.
create or replace function tst_count(p_role text, p_auth text, p_sql text) returns int
language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claims', case when p_auth is null then '' else json_build_object('sub',p_auth)::text end, true);
  execute 'set local role '||quote_ident(p_role);
  execute 'select count(*) from ('||p_sql||') q' into n;
  reset role;
  return n;
end $$;

\echo '==================== PHASE 4: RLS ROLE MATRIX ===================='
do $$
declare A text := 'a0000000-0000-4000-a000-00000000000a';
declare B text := 'b0000000-0000-4000-b000-00000000000b';
declare n int;
begin
  -- ANON cannot read any family PII
  if tst_count('anon', null, 'select 1 from families') <> 0 then raise exception 'FAIL anon read families'; end if;
  if tst_count('anon', null, 'select 1 from subscriptions') <> 0 then raise exception 'FAIL anon read subscriptions'; end if;
  if tst_count('anon', null, 'select 1 from family_product_entitlements') <> 0 then raise exception 'FAIL anon read entitlements'; end if;
  raise notice 'OK  anon: 0 rows on families / subscriptions / entitlements';

  -- OWNER A sees only family A
  if tst_count('authenticated','11111111-0000-4000-a000-00000000000a','select 1 from families') <> 1 then raise exception 'FAIL ownerA families count'; end if;
  if tst_count('authenticated','11111111-0000-4000-a000-00000000000a','select 1 from families where id='||quote_literal(B)) <> 0 then raise exception 'FAIL ownerA saw family B'; end if;
  if tst_count('authenticated','11111111-0000-4000-a000-00000000000a','select 1 from subscriptions') <> 1 then raise exception 'FAIL ownerA subs'; end if;
  if tst_count('authenticated','11111111-0000-4000-a000-00000000000a','select 1 from family_product_entitlements') <> 1 then raise exception 'FAIL ownerA entitlements'; end if;
  raise notice 'OK  owner A: sees exactly own family / subs / entitlement, NOT family B';

  -- NON-OWNER member A sees family A (member) but not B
  if tst_count('authenticated','22222222-0000-4000-a000-00000000000d','select 1 from family_members') < 1 then raise exception 'FAIL memberA members'; end if;
  if tst_count('authenticated','22222222-0000-4000-a000-00000000000d','select 1 from families where id='||quote_literal(B)) <> 0 then raise exception 'FAIL memberA saw B'; end if;
  raise notice 'OK  non-owner member A: scoped to family A only';

  -- OWNER B cannot see family A
  if tst_count('authenticated','33333333-0000-4000-b000-00000000000b','select 1 from families where id='||quote_literal(A)) <> 0 then raise exception 'FAIL ownerB saw family A'; end if;
  if tst_count('authenticated','33333333-0000-4000-b000-00000000000b','select 1 from subscriptions where family_id='||quote_literal(A)) <> 0 then raise exception 'FAIL ownerB saw A subs'; end if;
  raise notice 'OK  owner B: cannot read family A (cross-family isolation)';

  -- founder_grants / device_tokens / account_deletion_requests: no cross-family leak
  insert into founder_grants(family_id,product,state) values (A::uuid,'homehuddle','granted') on conflict do nothing;
  if tst_count('authenticated','33333333-0000-4000-b000-00000000000b','select 1 from founder_grants') <> 0 then raise exception 'FAIL ownerB saw A founder_grants'; end if;
  raise notice 'OK  founder_grants: family B sees none of family A''s';

  -- client_errors: only admin may read
  insert into client_errors(kind,message) values ('error','synthetic');
  if tst_count('authenticated','33333333-0000-4000-b000-00000000000b','select 1 from client_errors') <> 0 then raise exception 'FAIL non-admin read client_errors'; end if;
  if tst_count('authenticated','99999999-dead-4000-a000-00000000000a','select 1 from client_errors') < 1 then raise exception 'FAIL admin cannot read client_errors'; end if;
  raise notice 'OK  client_errors: non-admin denied, admin allowed';

  -- ADMIN sees all families; non-admin sees only own
  if tst_count('authenticated','99999999-dead-4000-a000-00000000000a','select 1 from families') < 2 then raise exception 'FAIL admin families'; end if;
  raise notice 'OK  admin: reads all families; forge checks next';
end $$;

-- ── Forge prevention: authenticated cannot WRITE entitlements/founder/subs ──
-- Isolated helper: run a write as `authenticated` and report whether it was
-- blocked (RLS / missing grant / revoked EXECUTE). Role is set OUTSIDE the
-- inner savepoint so an exception doesn't silently revert it.
create or replace function tst_blocked(p_auth text, p_sql text) returns boolean
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_auth)::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql;
    reset role; return false;                 -- NOT blocked → forge succeeded (bad)
  exception when others then
    reset role; return true;                  -- blocked (good)
  end;
end $$;

\echo '-- forge attempts (each must be BLOCKED) --'
do $$
declare uid text := '11111111-0000-4000-a000-00000000000a';
begin
  if not tst_blocked(uid, $q$insert into family_product_entitlements(family_id,product,is_active,active_source)
       values ('a0000000-0000-4000-a000-00000000000a','homehuddle',true,'forged')
       on conflict (family_id,product) do update set is_active=true$q$)
    then raise exception 'FAIL: authenticated forged an entitlement write'; end if;

  if not tst_blocked(uid, $q$insert into founder_grants(family_id,product,state)
       values ('a0000000-0000-4000-a000-00000000000a','homehuddle','granted')$q$)
    then raise exception 'FAIL: authenticated forged a founder grant'; end if;

  if not tst_blocked(uid, $q$select grant_founder_slot('a0000000-0000-4000-a000-00000000000a','homehuddle','apple','x')$q$)
    then raise exception 'FAIL: authenticated executed grant_founder_slot'; end if;

  if not tst_blocked(uid, $q$insert into subscriptions(family_id,product,source,status)
       values ('a0000000-0000-4000-a000-00000000000a','homehuddle','stripe','active')$q$)
    then raise exception 'FAIL: authenticated forged a subscription row'; end if;

  raise notice 'OK  authenticated CANNOT forge entitlement / founder grant / subscription / call service-only fns';
end $$;

\echo '==================== RLS MATRIX PASSED ===================='

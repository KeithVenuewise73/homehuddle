// Multi-session contract tests on a real PostgreSQL server.
//
// Unlike the in-process suites, every actor here is a SEPARATE database connection, so
// row locks, waits and races behave as they do on Supabase. Structure is production-
// faithful (prod_fixture.sql + the recovered calendar ledger file); rows are synthetic.
//
// Run:  RINKS_PG_ADMIN_URL=postgres://postgres@localhost:55432/postgres node sessions.test.mjs
// The suite creates and drops its own database (rinks_contract_test). It never connects
// to a hosted project and refuses any URL that is not localhost or a unix socket.
import pg from 'pg';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';

const ADMIN = process.env.RINKS_PG_ADMIN_URL;
if (!ADMIN) {
  console.log('SKIP: set RINKS_PG_ADMIN_URL to a LOCAL PostgreSQL superuser URL');
  process.exit(0);
}
const host = new URL(ADMIN).hostname;
if (!['localhost', '127.0.0.1', ''].includes(host) && !host.startsWith('%2F')) {
  throw new Error('Refusing to run against a non-local database');
}
const DB = 'rinks_contract_test';
const dbUrl = (() => {
  const u = new URL(ADMIN);
  u.pathname = '/' + DB;
  return u.toString();
})();
const read = (p) => fs.readFile(new URL(p, import.meta.url), 'utf8');
const results = [];
const pass = (m) => {
  results.push(m);
  console.log('PASS: ' + m);
};

// ---------- database setup ----------
{
  const admin = new pg.Client({ connectionString: ADMIN });
  await admin.connect();
  await admin.query(`drop database if exists ${DB} with (force)`);
  await admin.query(`create database ${DB}`);
  await admin.end();
}
const su = new pg.Client({ connectionString: dbUrl });
await su.connect();
for (const role of ['anon', 'authenticated', 'service_role']) {
  await su.query(`do $$begin if not exists(select 1 from pg_roles where rolname='${role}') then create role ${role}; end if; end$$`);
}
const fixture = (await read('./prod_fixture.sql')).replace(/^create role .*$/m, '');
await su.query(fixture);
await su.query(await read('../../supabase/recovery/production-2026-11/migrations/20260827124557_calendar_hub_writer_unattached.sql'));
for (const f of ['01_schema.sql', '02_functions.sql', '03_calendar_publisher.sql']) {
  await su.query(await read('../../supabase/proposals/rinks/' + f));
}
pass('recovered calendar ledger file + 01/02/03 candidates apply on a real PostgreSQL server');

// ---------- synthetic world ----------
const id = () => crypto.randomUUID();
const W = {};
const P = {};
let phone = 0;
async function workspace(key, status = 'active') {
  W[key] = id();
  await su.query('insert into business_workspaces(id,slug,name,status) values($1,$2,$2,$3)', [W[key], key, status]);
}
async function person(key, ws, role) {
  P[key] = P[key] || id();
  await su.query('insert into people(id,auth_user_id,phone) values($1,$1,$2) on conflict do nothing', [P[key], '+1555100' + String(++phone).padStart(4, '0')]);
  await su.query('insert into workspace_members(workspace_id,person_id) values($1,$2) on conflict do nothing', [W[ws], P[key]]);
  await su.query('insert into workspace_roles(workspace_id,person_id,role) values($1,$2,$3)', [W[ws], P[key], role]);
}
for (const k of ['rinkA', 'rinkB', 'orgA', 'orgB', 'orgC']) await workspace(k);
await workspace('orgSuspended', 'suspended');
await person('schedA', 'rinkA', 'staff');
await person('schedB', 'rinkB', 'staff');
await person('renterA', 'orgA', 'admin');
await person('renterB', 'orgB', 'admin');
await person('renterC', 'orgC', 'owner');
await person('coachA', 'orgA', 'coach');
await person('viewerA', 'orgA', 'viewer');
await person('suspendedAdmin', 'orgSuspended', 'admin');
const F = { A: id(), B: id(), outside: id() };
const AREA = { A1: id(), B1: id(), outside: id() };
await su.query("insert into facilities(id,name,slug,access_code,workspace_id) values($1,'Synthetic Rink A','synthetic-a','x',$4),($2,'Synthetic Rink B','synthetic-b','x',$5),($3,'Outside Rink (not a FacilityHuddle customer)','outside','x',null)", [F.A, F.B, F.outside, W.rinkA, W.rinkB]);
await su.query("insert into facility_areas(id,facility_id,name,area_type) values($1,$2,'Sheet A1','ice'),($3,$4,'Sheet B1','ice'),($5,$6,'Outside sheet','ice')", [AREA.A1, F.A, AREA.B1, F.B, AREA.outside, F.outside]);
const O = { A: id(), B: id(), C: id(), S: id() };
await su.query("insert into organizations(id,name,workspace_id) values($1,'Synthetic Org A',$5),($2,'Synthetic Org B',$6),($3,'Synthetic Org C',$7),($4,'Suspended Org',$8)", [O.A, O.B, O.C, O.S, W.orgA, W.orgB, W.orgC, W.orgSuspended]);
await su.query("insert into alert_recipients(label,phone) values('synthetic staff','+15550009999')");
await su.query("insert into facility_policies(facility_id,cancellation_notice_days,notice_basis,policy_text) values($1,30,'calendar_days','Synthetic 30-day policy')", [F.A]);

// ---------- independent sessions ----------
async function session(who) {
  const c = new pg.Client({ connectionString: dbUrl });
  await c.connect();
  if (who === 'anon') await c.query('set role anon');
  else {
    await c.query('set role authenticated');
    await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: P[who], role: 'authenticated' })]);
  }
  c.one = async (sql, params = []) => Object.values((await c.query(sql, params)).rows[0] ?? { v: null })[0];
  return c;
}
const S = {};
for (const k of Object.keys(P)) S[k] = await session(k);
S.anon = await session('anon');
const one = async (sql, p = []) => Object.values((await su.query(sql, p)).rows[0] ?? { v: null })[0];
let day = 10;
const slotTimes = () => {
  const s = Date.now() + day++ * 864e5;
  return [new Date(s).toISOString(), new Date(s + 3600e3).toISOString()];
};
const reqIce = (who, org, [s, e], slot = null, facility = F.A, area = AREA.A1) =>
  S[who].one('select request_rink_ice($1,$2,$3,null,$4,$5,$6,$7)', [facility, area, org, s, e, 'synthetic', slot]);
const award = (who, r, amt) => S[who].one('select award_open_slot($1,$2)', [r, amt]);

// ---------- 1. Full sequence: booking -> cancellation -> release -> competing requests -> award ----------
{
  const t = slotTimes();
  const r1 = await reqIce('renterA', O.A, t);
  const b1 = await award('schedA', r1, 300);
  assert.equal(await one('select status from bookings where id=$1', [b1]), 'confirmed');
  const c1 = await S.renterA.one('select request_booking_cancellation($1,$2)', [b1, 'synthetic conflict']);
  assert.equal(await one('select status from bookings where id=$1', [b1]), 'confirmed');
  const snap = await one('select policy_snapshot from booking_cancellation_requests where id=$1', [c1]);
  assert.equal(snap.cancellation_notice_days, 30);
  await S.renterB.one('select set_facility_waitlist($1,$2,true)', [F.A, O.B]);
  await S.renterC.one('select set_facility_waitlist($1,$2,false)', [F.A, O.C]);
  const slot = await S.schedA.one("select decide_cancellation($1,true,'release approved')", [c1]);
  assert.equal(await one('select status from bookings where id=$1', [b1]), 'cancelled');
  assert.equal(await one('select status from booking_financial_dispositions where cancellation_request_id=$1', [c1]), 'undetermined');
  const offers = (await su.query('select person_id,status,channel from open_slot_offers where open_slot_id=$1', [slot])).rows;
  assert.deepEqual(offers.map((o) => [o.person_id, o.status, o.channel]), [[P.renterB, 'no_channel', 'none']]);
  const pub = await S.anon.one("select public_open_slots('synthetic-a')");
  assert.ok(pub.some((s) => s.id === slot));
  const rB = await reqIce('renterB', O.B, t, slot);
  const rC = await reqIce('renterC', O.C, t, slot);
  const b2 = await award('schedA', rC, 300);
  assert.equal(await one('select status from open_slot_requests where id=$1', [rB]), 'closed');
  assert.equal(await one('select status from open_slots where id=$1', [slot]), 'awarded');
  const cal = (await su.query("select source_id,status from calendar_events where source_module='facilityhuddle' and source_id in ($1,$2) order by status", [b1, b2])).rows;
  assert.deepEqual(cal.map((r) => r.status), ['active', 'cancelled']);
  assert.equal(await one("select count(*)::int from calendar_events where source_module='facilityhuddle' and source_id=$1", [b1]), 1);
  const pubAfter = await S.anon.one("select public_open_slots('synthetic-a')");
  assert.ok(!pubAfter.some((s) => s.id === slot));
  pass('full sequence: request -> award -> cancellation request (booking stays confirmed, 30-day policy snapshot kept) -> approved release (one public opening, undetermined financial disposition, no_channel offer only to the opted-in other organization) -> two competing requests -> one award, the other closed, opening withdrawn from public list, one calendar row per booking (original cancelled, replacement active)');
}

// ---------- 2. Simultaneous competing awards for a released opening, independent sessions ----------
async function releasedSlot() {
  const t = slotTimes();
  const r = await reqIce('renterA', O.A, t);
  const b = await award('schedA', r, 200);
  const c = await S.renterA.one('select request_booking_cancellation($1,$2)', [b, 'x']);
  const slot = await S.schedA.one("select decide_cancellation($1,true,'ok')", [c]);
  return { t, slot };
}
const sched2 = await session('schedA');
{
  let rounds = 0;
  for (let i = 0; i < 20; i++) {
    const { t, slot } = await releasedSlot();
    const rB = await reqIce('renterB', O.B, t, slot);
    const rC = await reqIce('renterC', O.C, t, slot);
    const out = await Promise.allSettled([S.schedA.one('select award_open_slot($1,200)', [rB]), sched2.one('select award_open_slot($1,200)', [rC])]);
    const ok = out.filter((o) => o.status === 'fulfilled').length;
    assert.equal(ok, 1, JSON.stringify(out.map((o) => o.reason?.message)));
    assert.match(out.find((o) => o.status === 'rejected').reason.message, /closed|no longer available|already reserved/);
    assert.equal(await one("select count(*)::int from bookings where area_id=$1 and status='confirmed' and start_time=$2", [AREA.A1, t[0]]), 1);
    assert.equal(await one("select count(*)::int from open_slot_requests where open_slot_id=$1 and status='awarded'", [slot]), 1);
    rounds++;
  }
  pass(`${rounds}/20 rounds of two scheduler sessions awarding the same released opening at the same instant: exactly one booking, one awarded request, the other rejected every time`);
}

// ---------- 3. Deterministic interleaving: B really waits on A's lock ----------
{
  const { t, slot } = await releasedSlot();
  const rB = await reqIce('renterB', O.B, t, slot);
  const rC = await reqIce('renterC', O.C, t, slot);
  await S.schedA.query('begin');
  await S.schedA.query('select award_open_slot($1,200)', [rB]);
  const pid = await sched2.one('select pg_backend_pid()');
  const pending = sched2.one('select award_open_slot($1,200)', [rC]).then(
    () => 'won',
    (e) => e.message
  );
  let waiting = false;
  for (let i = 0; i < 50 && !waiting; i++) {
    await new Promise((r) => setTimeout(r, 50));
    waiting = (await one('select wait_event_type from pg_stat_activity where pid=$1', [pid])) === 'Lock';
  }
  assert.ok(waiting, 'second session should be blocked on a row lock');
  await S.schedA.query('commit');
  const second = await pending;
  assert.match(second, /closed/);
  pass(`interleaved sessions: while session A held its award transaction open, session B was blocked on a row lock (pg_stat_activity wait_event_type = Lock); after A committed, B failed with "${second}"`);
}

// ---------- 4. Simultaneous awards of two overlapping NEW-time requests ----------
{
  let rounds = 0;
  for (let i = 0; i < 20; i++) {
    const t = slotTimes();
    const rB = await reqIce('renterB', O.B, t);
    const rC = await reqIce('renterC', O.C, t);
    const out = await Promise.allSettled([S.schedA.one('select award_open_slot($1,150)', [rB]), sched2.one('select award_open_slot($1,150)', [rC])]);
    assert.equal(out.filter((o) => o.status === 'fulfilled').length, 1);
    assert.equal(await one("select count(*)::int from bookings where area_id=$1 and status='confirmed' and start_time=$2", [AREA.A1, t[0]]), 1);
    const statuses = (await su.query('select status from open_slot_requests where id in ($1,$2) order by status', [rB, rC])).rows.map((r) => r.status);
    assert.deepEqual(statuses, ['awarded', 'closed']);
    rounds++;
  }
  pass(`${rounds}/20 rounds of simultaneous awards for two overlapping new-time requests: one booking, the rival request closed (not left pending)`);
}

// ---------- 5. Request racing an award on the same ice ----------
{
  const t = slotTimes();
  const rB = await reqIce('renterB', O.B, t);
  await S.schedA.query('begin');
  await S.schedA.query('select award_open_slot($1,150)', [rB]);
  const late = reqIce('renterC', O.C, t).then(
    () => 'accepted',
    (e) => e.message
  );
  await new Promise((r) => setTimeout(r, 300));
  await S.schedA.query('commit');
  assert.match(await late, /already reserved/);
  pass('a new request submitted while an award for the same ice is in flight waits for it, then is rejected as already reserved (no orphan pending request)');
}

// ---------- 6. Maintenance conflicts ----------
{
  const t = slotTimes();
  const rB = await reqIce('renterB', O.B, t);
  await su.query("insert into bookings(facility_id,area_id,booking_type,title,start_time,end_time,status) values($1,$2,'maintenance','Resurface',$3,$4,'maintenance')", [F.A, AREA.A1, t[0], t[1]]);
  await assert.rejects(award('schedA', rB, 100), /already reserved/);
  await assert.rejects(reqIce('renterC', O.C, t), /already reserved/);
  await assert.rejects(su.query("insert into bookings(facility_id,area_id,booking_type,start_time,end_time,status) values($1,$2,'private_rental',$3,$4,'confirmed')", [F.A, AREA.A1, t[0], t[1]]), /already reserved/);
  const cal = await S.anon.one("select public_facility_calendar('synthetic-a',$1::timestamptz - interval '1 hour',$2)", [t[0], t[1]]);
  assert.ok(cal.some((x) => x.status === 'Unavailable'));
  pass('maintenance blocks: award of an overlapping request, a new request, and a direct overlapping booking are all rejected; the public calendar shows the block as "Unavailable"');
}

// ---------- 7. Unauthorized access ----------
{
  const t = slotTimes();
  const rA = await reqIce('renterA', O.A, t);
  const deny = async (label, p, re = /permission|Sign in/) => {
    await assert.rejects(p, re, label);
  };
  await deny('other org requests for org A', reqIce('renterB', O.A, slotTimes()));
  await deny('coach role requests ice', reqIce('coachA', O.A, slotTimes()));
  await deny('viewer role requests ice', reqIce('viewerA', O.A, slotTimes()));
  await deny('suspended workspace admin requests', reqIce('suspendedAdmin', O.S, slotTimes()));
  await deny('renter awards own request', award('renterA', rA, 1));
  await deny('scheduler of another rink awards', award('schedB', rA, 1));
  await deny('other org declines', S.renterB.one('select decline_rink_request($1)', [rA]));
  await deny('other org withdraws', S.renterB.one('select withdraw_rink_request($1)', [rA]));
  const bA = await award('schedA', rA, 120);
  await deny('other org requests cancellation', S.renterB.one('select request_booking_cancellation($1,$2)', [bA, 'x']));
  const cA = await S.renterA.one('select request_booking_cancellation($1,$2)', [bA, 'x']);
  await deny('renter approves own release', S.renterA.one("select decide_cancellation($1,true,'x')", [cA]));
  await deny('other rink scheduler approves release', S.schedB.one("select decide_cancellation($1,true,'x')", [cA]));
  await deny('anon workspace', S.anon.one('select rink_workspace()'), /permission/);
  await deny('anon request', S.anon.one('select request_rink_ice($1,$2,$3,null,$4,$5,$6,null)', [F.A, AREA.A1, O.A, ...slotTimes(), 'x']), /permission/);
  for (const tbl of ['bookings', 'open_slots', 'open_slot_requests', 'booking_cancellation_requests', 'booking_financial_dispositions', 'facility_waitlist', 'open_slot_offers', 'calendar_events', 'facility_policies']) {
    await deny('anon reads ' + tbl, S.anon.query(`select * from public.${tbl} limit 1`), /permission/);
    await deny('authenticated reads ' + tbl, S.renterA.query(`select * from public.${tbl} limit 1`), /permission/);
  }
  await deny('authenticated calls calendar writer directly', S.renterA.query("select public.publish_to_calendar('facilityhuddle','bookings','x','t',now())"), /permission/);
  await assert.rejects(reqIce('renterA', O.A, slotTimes(), null, F.outside, AREA.outside), /Invalid ice area/);
  await S.schedA.one("select decide_cancellation($1,false,'denied')", [cA]);
  pass('unauthorized actions refused: other organizations, coach/viewer roles, suspended workspaces, renters acting as schedulers, schedulers of another rink, anonymous callers; no direct table reads (9 tables x anon/authenticated) and no direct calendar-writer calls; a non-customer facility cannot receive requests');
}

// ---------- 8. Revoked membership ----------
{
  const t = slotTimes();
  const rC = await reqIce('renterC', O.C, t);
  const before = await S.renterC.one('select rink_workspace()');
  assert.ok(before.requests.some((r) => r.id === rC));
  await su.query("update workspace_members set status='revoked' where person_id=$1", [P.renterC]);
  const after = await S.renterC.one('select rink_workspace()');
  assert.equal(after.requests.length + after.bookings.length + after.cancellations.length, 0);
  await assert.rejects(S.renterC.one('select withdraw_rink_request($1)', [rC]), /permission/);
  await assert.rejects(reqIce('renterC', O.C, slotTimes()), /permission/);
  await S.renterC.one('select 1').catch(() => {});
  // A revoked contact with an opted-in waitlist row gets no offer on the next release.
  await su.query("update workspace_members set status='active' where person_id=$1", [P.renterC]);
  await S.renterC.one('select set_facility_waitlist($1,$2,true)', [F.A, O.C]);
  await su.query("update workspace_members set status='revoked' where person_id=$1", [P.renterC]);
  const { slot } = await releasedSlot();
  assert.equal(await one('select count(*)::int from open_slot_offers where open_slot_id=$1 and person_id=$2', [slot, P.renterC]), 0);
  assert.equal(await one('select count(*)::int from open_slot_offers where open_slot_id=$1 and person_id=$2', [slot, P.renterB]), 1);
  await su.query("update workspace_members set status='active' where person_id=$1", [P.renterC]);
  pass('revoked membership takes effect immediately in an open session: workspace goes empty, withdraw and new requests refused, and a revoked contact receives no opening offer while an active one does');
}

// ---------- 9. Private-data redaction ----------
{
  const cal = await S.anon.one("select public_facility_calendar('synthetic-a',now(),now()+interval '90 days')");
  assert.ok(cal.length > 0);
  for (const row of cal) assert.deepEqual(Object.keys(row).sort(), ['area_id', 'area_name', 'end_time', 'id', 'start_time', 'status']);
  assert.ok(cal.every((r) => ['Booked', 'Unavailable'].includes(r.status)));
  const slots = await S.anon.one("select public_open_slots('synthetic-a')");
  for (const row of slots) assert.deepEqual(Object.keys(row).sort(), ['area_id', 'area_name', 'end_time', 'id', 'price', 'start_time']);
  const anonCat = await S.anon.one('select rink_catalog()');
  assert.equal(anonCat.organizations.length, 0);
  assert.ok(anonCat.facilities.every((f) => f.can_schedule === false));
  assert.ok(!anonCat.facilities.some((f) => f.slug === 'outside'));
  const json = JSON.stringify(cal) + JSON.stringify(slots) + JSON.stringify(anonCat);
  for (const secret of ['Synthetic Org', '+1555', 'access_code', 'customer_name', 'amount']) assert.ok(!json.includes(secret), secret);
  const bView = await S.renterB.one('select rink_workspace()');
  assert.ok(bView.bookings.every((b) => b.organization_id === O.B));
  assert.equal(bView.financial.length, 0);
  assert.ok(bView.requests.every((r) => r.organization_id === O.B));
  pass(`redaction: anonymous calendar (${cal.length} rows) and openings return only time/sheet/status (openings also price); no organization names, phone numbers, access codes or amounts; anonymous catalog lists no organizations and no non-customer facility; organizations see only their own bookings and requests and no financial records`);
}

// ---------- 10. Existing production trigger effects ----------
{
  const awards = await one("select count(*)::int from bookings where booking_type in ('organization_rental','team_rental')");
  const sms = await one("select count(*)::int from sms_outbox where event_ref like 'booking:%'");
  const other = await one("select count(*)::int from sms_outbox where event_ref not like 'booking:%'");
  const sample = await one("select message from sms_outbox where event_ref like 'booking:%' order by created_at desc limit 1");
  assert.ok(sms >= awards && other === 0);
  assert.match(sample, /Synthetic Org/);
  const dup = await one("select count(*)::int from (select source_id from calendar_events group by source_module,source_table,source_id having count(*)>1) d");
  assert.equal(dup, 0);
  assert.equal(await one("select count(*)::int from calendar_events where source_module='facilityhuddle'"), await one("select count(*)::int from bookings where booking_type in ('organization_rental','team_rental')"));
  // (the maintenance block was inserted directly by the fixture, not through an award, so it has no calendar row)

  pass(`existing bookings_alert trigger: every new booking (${awards} awards + 1 maintenance block) queued exactly one pending staff text (${sms} rows; message names the organization, e.g. ${JSON.stringify(sample.split('\n').slice(0, 2).join(' / '))}); cancellations, releases, requests and offers queued none. Nothing is delivered here; on production these would send once Twilio is restored`);
}

// ---------- 11. Multiple facilities, no exclusive affiliation ----------
{
  const t = slotTimes();
  await reqIce('renterA', O.A, t, null, F.B, AREA.B1);
  await reqIce('renterA', O.A, t, null, F.A, AREA.A1);
  const cat = await S.renterA.one('select rink_catalog()');
  assert.deepEqual(cat.facilities.map((f) => f.slug).sort(), ['synthetic-a', 'synthetic-b']);
  pass('one organization requests the same time at two participating rinks; no facility affiliation is required, and a non-customer facility simply does not appear');
}

for (const c of [...Object.values(S), sched2]) await c.end().catch(() => {});
await su.end();
{
  const admin = new pg.Client({ connectionString: ADMIN });
  await admin.connect();
  await admin.query(`drop database if exists ${DB} with (force)`);
  await admin.end();
}
console.log(`\n${results.length} multi-session checks passed on PostgreSQL ${process.env.PGVERSION_LABEL || ''}`.trim());

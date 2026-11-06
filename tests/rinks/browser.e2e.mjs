// Browser workflow test: the REAL rink pages (facilityhuddle/rinks) driving the REAL candidate SQL
// on a local PostgreSQL server, one browser context per person.
//
// What is simulated, and only this: Supabase Auth and PostgREST. A small local RPC bridge stands in
// for supabase-js — it runs each rpc() as role `authenticated` with that person's JWT claims, exactly
// how PostgREST invokes functions. Sign-in itself (email link delivery, redirect URLs) is NOT tested here.
// Activation is switched on ONLY inside this test by intercepting assets/settings.js; the committed
// file stays enabled:false.
//
// Run: RINKS_PG_ADMIN_URL=postgres://postgres@localhost:55432/postgres node browser.e2e.mjs
import pg from 'pg';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const { chromium, devices } = createRequire(import.meta.url)('playwright');

const ADMIN = process.env.RINKS_PG_ADMIN_URL;
if (!ADMIN) {
  console.log('SKIP: set RINKS_PG_ADMIN_URL to a LOCAL PostgreSQL superuser URL');
  process.exit(0);
}
const host = new URL(ADMIN).hostname;
if (!['localhost', '127.0.0.1', ''].includes(host) && !host.startsWith('%2F')) throw new Error('Refusing non-local database');
const DB = 'rinks_browser_test';
const dbUrl = (() => {
  const u = new URL(ADMIN);
  u.pathname = '/' + DB;
  return u.toString();
})();
const here = new URL('.', import.meta.url);
const repoRoot = path.resolve(new URL('../../', here).pathname);
const read = (p) => fs.readFile(new URL(p, here), 'utf8');
const shots = process.env.RINKS_SHOTS_DIR;
const log = (m) => console.log('PASS: ' + m);

// ---------- database ----------
{
  const a = new pg.Client({ connectionString: ADMIN });
  await a.connect();
  await a.query(`drop database if exists ${DB} with (force)`);
  await a.query(`create database ${DB}`);
  await a.end();
}
const su = new pg.Client({ connectionString: dbUrl });
await su.connect();
for (const r of ['anon', 'authenticated', 'service_role']) await su.query(`do $$begin if not exists(select 1 from pg_roles where rolname='${r}') then create role ${r}; end if; end$$`);
await su.query((await read('./prod_fixture.sql')).replace(/^create role .*$/m, ''));
await su.query(await read('../../supabase/recovery/production-2026-11/migrations/20260827124557_calendar_hub_writer_unattached.sql'));
for (const f of ['01_schema.sql', '02_functions.sql', '03_calendar_publisher.sql']) await su.query(await read('../../supabase/proposals/rinks/' + f));

const id = () => crypto.randomUUID();
const P = { sched: id(), renterA: id(), renterB: id(), renterC: id() };
const W = { rink: id(), A: id(), B: id(), C: id() };
for (const [k, v] of Object.entries(W)) await su.query('insert into business_workspaces(id,slug,name) values($1,$2,$2)', [v, 'ws-' + k]);
let n = 0;
for (const [p, ws, role] of [['sched', 'rink', 'staff'], ['renterA', 'A', 'admin'], ['renterB', 'B', 'admin'], ['renterC', 'C', 'admin']]) {
  await su.query('insert into people(id,auth_user_id,phone) values($1,$1,$2)', [P[p], '+1555200000' + ++n]);
  await su.query('insert into workspace_members(workspace_id,person_id) values($1,$2)', [W[ws], P[p]]);
  await su.query('insert into workspace_roles(workspace_id,person_id,role) values($1,$2,$3)', [W[ws], P[p], role]);
}
const FAC = id(), AREA = id();
// Synthetic stand-in carrying the slug the page uses. Not real rink data.
await su.query("insert into facilities(id,name,slug,access_code,workspace_id) values($1,'Synthetic test rink','cazenovia','x',$2)", [FAC, W.rink]);
await su.query("insert into facility_areas(id,facility_id,name,area_type) values($1,$2,'Synthetic sheet','ice')", [AREA, FAC]);
const ORG = { A: id(), B: id(), C: id() };
for (const k of ['A', 'B', 'C']) await su.query('insert into organizations(id,name,workspace_id) values($1,$2,$3)', [ORG[k], 'Synthetic Org ' + k, W[k]]);

// ---------- RPC bridge (stands in for PostgREST) ----------
const pool = new pg.Pool({ connectionString: dbUrl, max: 8 });
async function rpc(who, name, args) {
  if (!/^[a-z_]+$/.test(name)) throw new Error('bad rpc');
  const c = await pool.connect();
  try {
    await c.query('begin');
    if (who) {
      await c.query('set local role authenticated');
      await c.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ sub: who, role: 'authenticated' })]);
    } else await c.query('set local role anon');
    const keys = Object.keys(args || {});
    const sql = `select public.${name}(${keys.map((k, i) => `${k} => $${i + 1}`).join(',')}) as v`;
    const r = await c.query(sql, keys.map((k) => args[k]));
    await c.query('commit');
    return { data: r.rows[0].v, error: null };
  } catch (e) {
    await c.query('rollback').catch(() => {});
    return { data: null, error: { message: e.message } };
  } finally {
    c.release();
  }
}
const stub = `(function(){window.supabase={createClient:function(){
  const who=()=>localStorage.getItem('__rinks_test_user');
  return {auth:{getUser:async()=>({data:{user:who()?{id:who()}:null},error:null}),
    signInWithOtp:async()=>({error:null}),signOut:async()=>{localStorage.removeItem('__rinks_test_user');return {error:null}}},
    rpc:async(name,args)=>{const r=await fetch('/__rpc',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({who:who(),name,args})});return r.json();}};
}};})();`;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.jpg': 'image/jpeg' };
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/__rpc') {
    let body = '';
    for await (const ch of req) body += ch;
    const { who, name, args } = JSON.parse(body);
    res.setHeader('content-type', 'application/json');
    return res.end(JSON.stringify(await rpc(who, name, args)));
  }
  let file = path.join(repoRoot, decodeURIComponent(url.pathname));
  if (!file.startsWith(repoRoot)) return res.writeHead(403).end();
  if (file.endsWith('/')) file += 'index.html';
  try {
    const data = await fs.readFile(file);
    res.setHeader('content-type', types[path.extname(file)] || 'application/octet-stream');
    res.end(data);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${server.address().port}/facilityhuddle/rinks/`;

// ---------- browser ----------
const browser = await chromium.launch();
const errors = [];
async function as(who, opts = {}) {
  const ctx = await browser.newContext(opts);
  await ctx.route(/supabase-js@.*\/supabase\.js$/, (r) => r.fulfill({ contentType: 'text/javascript', body: stub }));
  await ctx.route(/\/rinks\/assets\/settings\.js$/, (r) => r.fulfill({ contentType: 'text/javascript', body: 'window.VW_RINKS=Object.freeze({enabled:true});' }));
  await ctx.addInitScript((w) => {
    if (w) localStorage.setItem('__rinks_test_user', w);
  }, who ? P[who] : null);
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('dialog', (d) => d.dismiss());
  return page;
}
const settle = (page) => page.waitForFunction(() => !document.querySelector('button[disabled][data-action]') || true).then(() => page.waitForTimeout(400));
async function open(page, view) {
  await page.goto(BASE + '?rink=cazenovia');
  await page.waitForTimeout(700);
  if (view) {
    await page.click(`button[data-action=${view}]`);
    await page.waitForTimeout(700);
  }
}
const text = (page) => page.textContent('main');
const easternLocal = (days, hour) => {
  const d = new Date(Date.now() + days * 864e5);
  const ymd = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(d);
  return `${ymd}T${String(hour).padStart(2, '0')}:00`;
};

const renterA = await as('renterA');
const sched = await as('sched');
const renterB = await as('renterB');
const renterC = await as('renterC');
const visitor = await as(null);

// 1. Organization requests a new time.
await open(renterA, 'request');
await renterA.selectOption('select[name=org]', ORG.A);
await renterA.fill('input[name=start]', easternLocal(3, 18));
await renterA.fill('input[name=end]', easternLocal(3, 19));
await renterA.fill('textarea[name=note]', 'Synthetic browser test');
await renterA.click('form#request button');
await renterA.waitForTimeout(900);
assert.match(await renterA.textContent('body'), /Request received/);
assert.equal(await su.query("select count(*)::int c from open_slot_requests where status='requested'").then((r) => r.rows[0].c), 1);
const startUtc = (await su.query('select start_time from open_slot_requests limit 1')).rows[0].start_time;
const expectUtc = new Date(new Date(easternLocal(3, 18) + ':00Z').getTime());
log(`organization scheduler requested ice through the page; stored start ${startUtc.toISOString()} for Eastern ${easternLocal(3, 18)} (offset ${(expectUtc - startUtc) / -36e5}h)`);

// 2. Scheduler awards it at an agreed price.
await open(sched, 'workspace');
assert.match(await text(sched), /RINK SCHEDULER/);
assert.match(await text(sched), /Synthetic Org A/);
await sched.fill('form[data-award] input[name=amount]', '275');
await sched.click('form[data-award] button');
await sched.waitForTimeout(900);
assert.match(await sched.textContent('body'), /Reservation confirmed/);
assert.equal((await su.query("select count(*)::int c from bookings where status='confirmed'")).rows[0].c, 1);
log('rink scheduler awarded the request from the workspace; one confirmed booking and one calendar entry exist');

// 3. Visitor sees "Booked" with no renter details.
await open(visitor);
const pub1 = await text(visitor);
assert.match(pub1, /Booked/);
assert.ok(!/Synthetic Org/.test(pub1) && !/275/.test(pub1));
log('public calendar shows the reservation as "Booked" with no organization name or price');

// 4. Renter requests cancellation; booking stays confirmed.
await open(renterA, 'workspace');
await renterA.fill('form[data-cancel] input[name=reason]', 'Synthetic tournament conflict');
await renterA.click('form[data-cancel] button');
await renterA.waitForTimeout(900);
assert.match(await renterA.textContent('body'), /reservation remains active/i);
assert.equal((await su.query('select status from bookings')).rows[0].status, 'confirmed');
log('renter requested cancellation from the page; the booking is still confirmed');

// 5. Another organization joins the opening list.
await open(renterB, 'waitlist');
await renterB.selectOption('select[name=org]', ORG.B);
await renterB.check('input[name=optin]');
await renterB.click('form#waitlist button');
await renterB.waitForTimeout(900);
assert.match(await renterB.textContent('body'), /No notification was sent/);
log('a second organization joined the opening list; the page says no notification was sent');

// 6. Scheduler approves the release.
await open(sched, 'workspace');
await sched.click('button[data-decide][data-approve=true]');
await sched.waitForTimeout(900);
const s6 = await text(sched);
assert.match(s6, /no channel/i);
assert.match(s6, /undetermined/);
log('scheduler approved the release; the workspace shows the offer as "no channel" and the financial review as "undetermined"');

// 7. Public sees the opening; two organizations request it.
await open(visitor);
assert.match(await text(visitor), /AVAILABLE ICE/);
for (const [page, org] of [[renterB, ORG.B], [renterC, ORG.C]]) {
  await open(page);
  await page.click('button[data-slot]');
  await page.waitForTimeout(500);
  await page.selectOption('select[name=org]', org);
  await page.click('form#request button');
  await page.waitForTimeout(900);
  assert.match(await page.textContent('body'), /Request received/);
}
assert.equal((await su.query("select count(*)::int c from open_slot_requests where open_slot_id is not null and status='requested'")).rows[0].c, 2);
log('the released opening appeared on the public page and two organizations requested it');

// 8. Scheduler awards one; the other closes; the opening leaves the public page.
await open(sched, 'workspace');
await sched.fill('form[data-award] input[name=amount]', '275');
await sched.click('form[data-award] button');
await sched.waitForTimeout(900);
const st = (await su.query('select status, count(*)::int c from open_slot_requests where open_slot_id is not null group by status order by status')).rows;
assert.deepEqual(st.map((r) => [r.status, r.c]), [['awarded', 1], ['closed', 1]]);
await open(visitor);
const pub2 = await text(visitor);
assert.ok(!/AVAILABLE ICE/.test(pub2));
assert.match(pub2, /Booked/);
log('scheduler awarded one competing request; the other closed automatically; the opening left the public page and the slot shows "Booked"');
const losing = (await su.query("select organization_id from open_slot_requests where status='closed'")).rows[0].organization_id;
const loserPage = losing === ORG.B ? renterB : renterC;
await open(loserPage, 'workspace');
assert.match(await text(loserPage), /closed/);
log('the losing organization sees its request as "closed" in its own workspace');

// 9. Calendar integrity.
const cal = (await su.query("select status from calendar_events where source_module='facilityhuddle' order by status")).rows.map((r) => r.status);
assert.deepEqual(cal, ['active', 'cancelled']);
log('calendar: exactly two rows (original cancelled, replacement active); no duplicates');

// 10. Official schedule links preserved; mobile layout.
await open(visitor);
const links = await visitor.$$eval('a[href]', (as) => as.map((a) => a.href));
for (const l of ['https://www.cazenoviarink.org/ice-bookings-info', 'https://www.cazenoviarink.org/public-skate']) assert.ok(links.includes(l), l);
await visitor.goto(BASE + '?rink=riverside');
await visitor.waitForTimeout(600);
const rlinks = await visitor.$$eval('a[href]', (as) => as.map((a) => a.href));
for (const l of ['https://www.riversiderink.org/rink-schedule', 'https://www.riversiderink.org/publicskate']) assert.ok(rlinks.includes(l), l);
log('current official schedule and public-skate links are present on both rink views');

const overflow = [];
for (const [name, who, view] of [['public-cazenovia', null, null], ['public-riverside', null, 'riverside'], ['workspace-scheduler', 'sched', 'workspace'], ['request-form', 'renterA', 'request']]) {
  const page = await as(who, { ...devices['iPhone 13'] });
  await page.goto(BASE + (view === 'riverside' ? '?rink=riverside' : '?rink=cazenovia'));
  await page.waitForTimeout(700);
  if (view && view !== 'riverside') {
    await page.click(`button[data-action=${view}]`);
    await page.waitForTimeout(700);
  }
  const m = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, iw: window.innerWidth }));
  if (m.sw > m.iw + 1) overflow.push(`${name}: page ${m.sw}px wide on a ${m.iw}px screen`);
  if (shots) await page.screenshot({ path: path.join(shots, `mobile-${name}.png`), fullPage: false });
  await page.context().close();
}
if (overflow.length) console.log('FINDING: horizontal overflow on phone width — ' + overflow.join('; '));
else log('phone width (iPhone 13, 390px): no horizontal scrolling on public, request or workspace views');

assert.deepEqual(errors, []);
log('no JavaScript errors in any page');
await browser.close();
server.close();
await pool.end();
await su.end();
{
  const a = new pg.Client({ connectionString: ADMIN });
  await a.connect();
  await a.query(`drop database if exists ${DB} with (force)`);
  await a.end();
}

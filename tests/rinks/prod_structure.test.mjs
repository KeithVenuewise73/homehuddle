// Claude's independent check: candidate SQL against PRODUCTION-FAITHFUL table structure
// (real columns, NOT NULLs, CHECKs, FKs, RLS-on, and the live bookings_alert trigger).
// Synthetic rows only. Each finding is printed as PASS / FINDING with evidence.
import {PGlite} from '@electric-sql/pglite';import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const db=new PGlite();const read=p=>fs.readFile(new URL(p,import.meta.url),'utf8');
const out=(tag,msg)=>console.log(`${tag}: ${msg}`);
await db.exec(await read('./prod_fixture.sql'));
for(const f of ['01_schema.sql','02_functions.sql'])await db.exec(await read('../../supabase/proposals/rinks/'+f));
out('PASS','01_schema.sql + 02_functions.sql apply cleanly on production structure (incl. open_slots_status_check swap, RLS-on tables, existing trigger)');
const q=(s,p=[])=>db.query(s,p);const one=async(s,p=[])=>Object.values((await q(s,p)).rows[0]??{x:null})[0];
const id=()=>crypto.randomUUID();const ids={};for(const k of ['sched','rentA','rentB','rentC','wsRink','wsA','wsB','wsC','rink','area','orgA','orgB','orgC'])ids[k]=id();
await q("insert into business_workspaces(id,slug,name) values($1,'rink','Rink'),($2,'a','A'),($3,'b','B'),($4,'c','C')",[ids.wsRink,ids.wsA,ids.wsB,ids.wsC]);
let n=0;for(const [p,ws,role] of [['sched','wsRink','staff'],['rentA','wsA','admin'],['rentB','wsB','admin'],['rentC','wsC','admin']]){n++;await q('insert into people(id,auth_user_id,phone) values($1,$1,$2)',[ids[p],'+1555000000'+n]);await q('insert into workspace_members(workspace_id,person_id) values($1,$2)',[ids[ws],ids[p]]);await q('insert into workspace_roles(workspace_id,person_id,role) values($1,$2,$3)',[ids[ws],ids[p],role]);}
await q("insert into facilities(id,name,slug,access_code,workspace_id) values($1,'Synthetic Rink','synthetic','x',$2)",[ids.rink,ids.wsRink]);
await q("insert into facility_areas(id,facility_id,name,area_type) values($1,$2,'Sheet 1','ice')",[ids.area,ids.rink]);
await q("insert into organizations(id,name,workspace_id) values($1,'Org A',$2),($3,'Org B',$4),($5,'Org C',$6)",[ids.orgA,ids.wsA,ids.orgB,ids.wsB,ids.orgC,ids.wsC]);
// a synthetic staff alert recipient, as production has (alert_recipients.alert_bookings defaults true)
await q("insert into alert_recipients(label,phone) values('synthetic staff','+15550009999')");
const as=async(p,fn)=>{await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[ids[p]]);try{return await fn()}finally{await db.exec('reset role')}};
const t0=Date.now()+10*864e5,iso=x=>new Date(x).toISOString();
const S=iso(t0),E=iso(t0+3600e3);

// 1. Full lifecycle on real structure
const r1=await as('rentA',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgA,S,E,'synthetic']));
const b1=await as('sched',()=>one('select award_open_slot($1,300)',[r1]));
assert.equal(await one('select count(*)::int from calendar_events'),1);
out('PASS','award creates a real bookings row on production columns (booking_type/status checks satisfied) and one calendar_events row');

// 2. Existing production trigger side effect
const sms=await one("select count(*)::int from sms_outbox where event_ref=$1",['booking:'+b1]);
if(sms>0){const m=await one("select message from sms_outbox where event_ref=$1",['booking:'+b1]);out('FINDING',`award fires the existing bookings_alert trigger: ${sms} pending sms_outbox row(s) queued to staff alert recipients. Message: ${JSON.stringify(m)}. send-sms-outbox cron runs every 2 min; this would send the moment Twilio is reactivated.`);}else out('PASS','no SMS queued by award');

// 3. Cancellation lifecycle, single calendar row
const c1=await as('rentA',()=>one('select request_booking_cancellation($1,$2)',[b1,'synthetic conflict']));
assert.equal(await one('select status from bookings where id=$1',[b1]),'confirmed');
await as('rentB',()=>one('select set_facility_waitlist($1,$2,true)',[ids.rink,ids.orgB]));
const slot=await as('sched',()=>one("select decide_cancellation($1,true,'ok')",[c1]));
assert.equal(await one('select count(*)::int from calendar_events'),1);assert.equal(await one('select status from calendar_events'),'cancelled');
out('PASS','pending cancellation keeps booking confirmed; approval cancels it, releases one public opening, same calendar row set to cancelled (no duplicate)');

// 4. Price exposure on the public listing
await db.exec('set role anon');const pub=await one("select public_open_slots('synthetic')");await db.exec('reset role');
out(pub[0]?.price==300?'FINDING':'PASS',`anonymous public_open_slots shows price ${pub[0]?.price} for the released slot: it is copied from the original renter's booking amount (decide_cancel sets price=b.amount). Confirm with the rinks that a renter's negotiated price may be published as the opening price.`);

// 5. Denied cancellation path
const b2s=iso(t0+2*864e5),b2e=iso(t0+2*864e5+3600e3);
const r2=await as('rentA',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgA,b2s,b2e,'synthetic']));
const b2=await as('sched',()=>one('select award_open_slot($1,100)',[r2]));
const c2=await as('rentA',()=>one('select request_booking_cancellation($1,$2)',[b2,'x']));
await as('sched',()=>one("select decide_cancellation($1,false,'no')",[c2]));
assert.equal(await one('select status from bookings where id=$1',[b2]),'confirmed');assert.equal(await one('select status from booking_cancellation_requests where id=$1',[c2]),'denied');
assert.equal(await one('select count(*)::int from open_slots where cancellation_request_id=$1',[c2]),0);
out('PASS','denied cancellation leaves booking confirmed and releases nothing');

// 6. Competing requests for the same NEW time (no published opening)
const s3=iso(t0+3*864e5),e3=iso(t0+3*864e5+3600e3);
const rA=await as('rentA',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgA,s3,e3,'synthetic']));
const rC=await as('rentC',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgC,s3,e3,'synthetic']));
await as('sched',()=>one('select award_open_slot($1,100)',[rA]));
const stC=await one('select status from open_slot_requests where id=$1',[rC]);
out(stC==='closed'?'PASS':'FINDING',`awarding one request closes the competing request for the same new time (status '${stC}')`);
// 6b. Scheduler can decline; renter can withdraw; nobody else can
const s6=iso(t0+4*864e5),e6=iso(t0+4*864e5+3600e3);
const rD=await as('rentA',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgA,s6,e6,'synthetic']));
await assert.rejects(as('rentC',()=>one('select decline_rink_request($1)',[rD])),/permission/);
await assert.rejects(as('rentC',()=>one('select withdraw_rink_request($1)',[rD])),/permission/);
await as('sched',()=>one('select decline_rink_request($1)',[rD]));
assert.equal(await one('select status from open_slot_requests where id=$1',[rD]),'closed');
const rW=await as('rentA',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgA,s6,e6,'again']));
await as('rentA',()=>one('select withdraw_rink_request($1)',[rW]));
assert.equal(await one('select status from open_slot_requests where id=$1',[rW]),'withdrawn');
out('PASS','scheduler can decline and the requesting organization can withdraw a pending request; other organizations cannot do either');

// 7. Requests after a time is already taken
let lateErr='';try{await as('rentC',()=>one('select request_rink_ice($1,$2,$3,null,$4,$5,$6)',[ids.rink,ids.area,ids.orgC,s3,e3,'late']))}catch(e){lateErr=e.message}
assert.match(lateErr,/already reserved/);out('PASS','new requests for already-booked ice are rejected');

// 8. Legacy-row compatibility of the new BEFORE trigger
const legacyArea=id();await q("insert into facility_areas(id,facility_id,name,area_type,is_active) values($1,$2,'Old room','room',true)",[legacyArea,ids.rink]);
const lb=await one("insert into bookings(facility_id,area_id,booking_type,start_time,end_time,status) values($1,$2,'private_rental',$3,$4,'confirmed') returning id",[ids.rink,legacyArea,iso(t0+5*864e5),iso(t0+5*864e5+3600e3)]);
await q('update facility_areas set is_active=false where id=$1',[legacyArea]);
let legacyErr='';try{await q("update bookings set status='cancelled' where id=$1",[lb])}catch(e){legacyErr=e.message}
out(legacyErr?'FINDING':'PASS',legacyErr?`cancelling a booking on a deactivated area fails: "${legacyErr}"`:'a booking on a since-deactivated area can still be cancelled (the new trigger never blocks a release)');
// 9. Anonymous isolation on real RLS posture
await db.exec('set role anon');let anonErr='';try{await q('select * from bookings')}catch(e){anonErr=e.message}
let wsErr='';try{await q('select rink_workspace()')}catch(e){wsErr=e.message}
const cal=await one("select public_facility_calendar('synthetic',now(),now()+interval '30 days')");await db.exec('reset role');
assert.ok(anonErr&&wsErr);assert.ok(cal.every(x=>!('organization_id' in x)&&!('amount' in x)));
out('PASS',`anon cannot read bookings ("${anonErr}") or the workspace; the public calendar returns no organization, renter or amount fields (${cal.length} rows)`);

// 10. Cross-organization isolation
const vB=await as('rentB',()=>one('select rink_workspace()'));
assert.ok(vB.bookings.every(b=>b.organization_id===ids.orgB));assert.equal(vB.financial.length,0);
out('PASS',`another organization sees only its own bookings (${vB.bookings.length}) and no financial records`);
console.log('NOT TESTED HERE: two independent sessions awarding at the same instant (PGlite is single-connection); Supabase Auth email sign-in; the other ~85 production tables and their triggers.');
await db.close();

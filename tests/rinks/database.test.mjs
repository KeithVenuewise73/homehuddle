import {PGlite} from '@electric-sql/pglite';import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const db=new PGlite();const read=p=>fs.readFile(new URL(p,import.meta.url),'utf8');
await db.exec(await read('./fixture.sql'));await db.exec(await read('../../supabase/recovery/production-2026-11/migrations/20260827124557_calendar_hub_writer_unattached.sql'));for(const file of ['01_schema.sql','02_functions.sql','03_calendar_publisher.sql'])await db.exec(await read('../../supabase/proposals/rinks/'+file));
const uuid=()=>crypto.randomUUID(),ids={};for(const k of ['scheduler','renter','other','wsRink','wsOrg','wsOther','rink','rink2','area','area2','org','otherOrg','team'])ids[k]=uuid();
const q=(s,p=[])=>db.query(s,p);const scalar=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
await q('insert into business_workspaces values ($1),($2),($3)',[ids.wsRink,ids.wsOrg,ids.wsOther]);for(const [person,ws,role] of [['scheduler','wsRink','staff'],['renter','wsOrg','admin'],['other','wsOther','admin']]){await q('insert into people(id,auth_user_id) values($1,$1)',[ids[person]]);await q("insert into workspace_members values($1,$2,'active')",[ids[ws],ids[person]]);await q('insert into workspace_roles values($1,$2,$3)',[ids[ws],ids[person],role]);}
await q("insert into facilities(id,name,slug,workspace_id) values($1,'Test Rink A','test-a',$3),($2,'Test Rink B','test-b',$3)",[ids.rink,ids.rink2,ids.wsRink]);await q("insert into facility_areas(id,facility_id,name,area_type) values($1,$2,'Ice A','ice'),($3,$4,'Ice B','ice')",[ids.area,ids.rink,ids.area2,ids.rink2]);await q("insert into organizations(id,name,workspace_id) values($1,'Test Organization',$2),($3,'Other Organization',$4)",[ids.org,ids.wsOrg,ids.otherOrg,ids.wsOther]);await q("insert into teams(id,organization_id,name) values($1,$2,'Test Team')",[ids.team,ids.org]);
async function as(person,fn){await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[ids[person]]);try{return await fn()}finally{await db.exec('reset role')}}
const start=new Date(Date.now()+7*864e5).toISOString(),end=new Date(Date.now()+7*864e5+3600e3).toISOString();
const requestArgs=[ids.rink,ids.area,ids.org,ids.team,start,end,'Synthetic test only'];
let request=await as('renter',()=>scalar('select request_rink_ice($1,$2,$3,$4,$5,$6,$7)',requestArgs));
await assert.rejects(as('other',()=>scalar('select request_rink_ice($1,$2,$3,$4,$5,$6,$7)',requestArgs)),/permission/);
await assert.rejects(as('renter',()=>scalar('select award_open_slot($1,250)',[request])),/permission/);
let booking=await as('scheduler',()=>scalar('select award_open_slot($1,250)',[request]));
assert.equal(await scalar('select count(*)::int from calendar_events'),1);
let cancellation=await as('renter',()=>scalar('select request_booking_cancellation($1,$2)',[booking,'Tournament conflict']));
assert.equal(await scalar('select status from bookings where id=$1',[booking]),'confirmed');
await assert.rejects(as('renter',()=>scalar('select request_booking_cancellation($1,$2)',[booking,'Duplicate'])),/unique/);
await as('other',()=>scalar('select set_facility_waitlist($1,$2,true)',[ids.rink,ids.otherOrg]));
let slot=await as('scheduler',()=>scalar("select decide_cancellation($1,true,'Approved release only')",[cancellation]));
assert.equal(await scalar('select status from bookings where id=$1',[booking]),'cancelled');assert.equal(await scalar('select status from booking_financial_dispositions'),'undetermined');assert.equal(await scalar('select status from open_slot_offers'),'no_channel');assert.equal(await scalar('select count(*)::int from calendar_events'),1);assert.equal(await scalar('select status from calendar_events'),'cancelled');
let replacement=await as('other',()=>scalar('select request_rink_ice($1,$2,$3,null,$4,$5,$6,$7)',[ids.rink,ids.area,ids.otherOrg,start,end,'Replacement',slot]));
await as('scheduler',()=>scalar('select award_open_slot($1,250)',[replacement]));await assert.rejects(as('scheduler',()=>scalar('select award_open_slot($1,250)',[replacement])),/closed/);assert.equal(await scalar('select status from open_slots where id=$1',[slot]),'awarded');
await assert.rejects(q("insert into bookings(facility_id,area_id,organization_id,start_time,end_time,status) values($1,$2,$3,$4,$5,'maintenance')",[ids.rink,ids.area,ids.org,start,end]),/reserved/);
// Same org/team may request another facility; there is no exclusive affiliation.
await as('renter',()=>scalar('select request_rink_ice($1,$2,$3,$4,$5,$6,$7)',[ids.rink2,ids.area2,ids.org,ids.team,start,end,'Second facility']));
await db.exec('set role anon');const publicEvents=await scalar("select public_facility_calendar('test-a',now(),now()+interval '30 days')");assert.equal(publicEvents.length,1);assert.deepEqual(Object.keys(publicEvents[0]).sort(),['id','area_id','area_name','start_time','end_time','status'].sort());await assert.rejects(q('select * from bookings'),/permission/);await assert.rejects(q('select rink_workspace()'),/permission/);await db.exec('reset role');
const otherView=await as('other',()=>scalar('select rink_workspace()'));assert.equal(otherView.bookings.length,1);assert.ok(otherView.bookings.every(b=>b.organization_id===ids.otherOrg));
await q("update workspace_members set status='revoked' where person_id=$1",[ids.other]);await assert.rejects(as('other',()=>scalar('select set_facility_waitlist($1,$2,true)',[ids.rink,ids.otherOrg])),/permission/);
console.log('PASS: request authorization, scheduler-only awards, pending cancellation preserves booking, duplicate cancellation rejected, approved release, undetermined financial disposition, truthful no-channel offers, unique calendar source, single award, maintenance overlap rejected, multiple facilities, anonymous redaction, cross-organization isolation, revoked membership.');
await db.close();

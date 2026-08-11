-- ============================================================================
-- Demo review family (App Review) — SYNTHETIC DATA ONLY
-- Seed this in the project used for the review build, alongside a Supabase Auth
-- *test phone number* (+1 555 010 0100 / fixed code) configured in the dashboard.
-- Idempotent. ⚠️ REVIEW ONLY — DO NOT APPLY blindly to production; run once
-- intentionally for the review build.
-- ============================================================================
begin;

-- Fixed ids so re-running is idempotent.
insert into public.families (id, family_name, email, phone, pin, status, sms_consent)
values ('00000000-0000-4000-a000-0000000000d0', 'Demo Reviewer Family',
        'appreview@venuewise.net', '+15550100100', '0000', 'active', false)
on conflict (id) do update set status = 'active';

insert into public.family_members (id, family_id, name, role, is_owner, can_add_events, can_edit_events)
values
 ('00000000-0000-4000-a000-0000000000d1','00000000-0000-4000-a000-0000000000d0','Alex Reviewer','parent',true,true,true),
 ('00000000-0000-4000-a000-0000000000d2','00000000-0000-4000-a000-0000000000d0','Sam (age 10)','child',false,false,false)
on conflict (id) do nothing;

-- A sample subscription so the reviewer sees an active entitlement (Standard).
insert into public.subscriptions (family_id, product, source, status, current_period_end)
values ('00000000-0000-4000-a000-0000000000d0','homehuddle','apple','active', now() + interval '30 days')
on conflict (family_id, product, source) do update set status = 'active';

select public.recompute_entitlement('00000000-0000-4000-a000-0000000000d0','homehuddle');

-- A sample calendar feed so games render (public sample iCal — replace as needed).
insert into public.feeds (family_name, email, kid_name, sport, platform, ical_url, is_active, status)
values ('Demo Reviewer Family','appreview@venuewise.net','Sam','Hockey','demo',
        'https://venuewise.net/homehuddle/calendar.html', true, 'active')
on conflict do nothing;

commit;

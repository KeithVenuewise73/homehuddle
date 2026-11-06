begin;
create function rink_private.has_role(p_workspace uuid,p_roles text[]) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.workspace_members m join public.workspace_roles r using(workspace_id,person_id) join public.people p on p.id=m.person_id where p.auth_user_id=auth.uid() and m.workspace_id=p_workspace and m.status='active' and r.role=any(p_roles));
$$;
create function rink_private.scheduler(p_facility uuid) returns boolean language sql stable security definer set search_path='' as $$select rink_private.has_role((select workspace_id from public.facilities where id=p_facility),array['owner','admin','staff'])$$;
create function rink_private.renter(p_org uuid) returns boolean language sql stable security definer set search_path='' as $$select rink_private.has_role((select workspace_id from public.organizations where id=p_org),array['owner','admin'])$$;

create function rink_private.public_calendar(p_slug text,p_from timestamptz,p_to timestamptz) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_to<=p_from or p_to-p_from>interval '93 days' then raise exception 'Choose a calendar range of 1–93 days'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'area_id',a.id,'area_name',a.name,'start_time',b.start_time,'end_time',b.end_time,'status',case when b.status='maintenance' then 'Unavailable' else 'Booked' end) order by b.start_time) from public.bookings b join public.facilities f on f.id=b.facility_id join public.facility_areas a on a.id=b.area_id where f.slug=p_slug and f.is_active and b.status in ('confirmed','maintenance') and b.start_time<p_to and b.end_time>p_from),'[]'::jsonb);
end $$;
create function rink_private.public_slots(p_slug text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'area_id',a.id,'area_name',a.name,'start_time',s.start_time,'end_time',s.end_time,'price',s.price) order by s.start_time),'[]'::jsonb) from public.open_slots s join public.facilities f on f.id=s.facility_id join public.facility_areas a on a.id=s.area_id where f.slug=p_slug and f.is_active and s.is_public and s.status='open' and s.start_time>now() and not exists(select 1 from public.bookings b where b.area_id=s.area_id and b.status in ('confirmed','maintenance') and b.start_time<s.end_time and b.end_time>s.start_time);
$$;
create function rink_private.catalog() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('facilities',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'slug',f.slug,'areas',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name)) from public.facility_areas a where a.facility_id=f.id and a.is_active and a.area_type='ice'),'[]'::jsonb),'can_schedule',rink_private.scheduler(f.id))) from public.facilities f where f.is_active and f.workspace_id is not null),'[]'::jsonb),'organizations',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'teams',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name)) from public.teams t where t.organization_id=o.id and t.is_active),'[]'::jsonb))) from public.organizations o where rink_private.renter(o.id)),'[]'::jsonb));
$$;
create function rink_private.workspace() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 return jsonb_build_object(
 'bookings',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'facility_id',b.facility_id,'area_id',b.area_id,'organization_id',b.organization_id,'team_id',b.team_id,'title',b.title,'start_time',b.start_time,'end_time',b.end_time,'amount',b.amount,'status',b.status) order by b.start_time) from public.bookings b where rink_private.scheduler(b.facility_id) or rink_private.renter(b.organization_id)),'[]'::jsonb),
 'cancellations',coalesce((select jsonb_agg(to_jsonb(c)) from public.booking_cancellation_requests c join public.bookings b on b.id=c.booking_id where rink_private.scheduler(b.facility_id) or rink_private.renter(b.organization_id)),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(to_jsonb(r)) from public.open_slot_requests r where rink_private.scheduler(r.facility_id) or rink_private.renter(r.organization_id)),'[]'::jsonb),
 'offers',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'open_slot_id',o.open_slot_id,'channel',o.channel,'status',o.status,'created_at',o.created_at)) from public.open_slot_offers o join public.open_slots s on s.id=o.open_slot_id where rink_private.scheduler(s.facility_id) or o.person_id=public.current_person_id()),'[]'::jsonb),
 'financial',coalesce((select jsonb_agg(to_jsonb(d)) from public.booking_financial_dispositions d join public.bookings b on b.id=d.booking_id where rink_private.scheduler(b.facility_id)),'[]'::jsonb),
 'waitlist',coalesce((select jsonb_agg(to_jsonb(w)) from public.facility_waitlist w where w.contact_person_id=public.current_person_id()),'[]'::jsonb));
end $$;
-- Reuse the calendar table with an atomic source-key upsert. This internal writer
-- does not alter other modules' existing publishing function or legacy calendars.
create function rink_private.publish_booking(p_booking uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v_event uuid;
begin
 insert into public.calendar_events(source_module,source_table,source_id,title,start_time,end_time,event_type,location_name,location_address,organization_id,facility_id,is_public,status)
 select 'facilityhuddle','bookings',b.id::text,coalesce(b.title,'Ice reservation'),b.start_time,b.end_time,b.booking_type,f.name,f.address,b.organization_id,b.facility_id,false,case when b.status='cancelled' then 'cancelled' else 'active' end from public.bookings b join public.facilities f on f.id=b.facility_id where b.id=p_booking
 on conflict(source_module,source_table,source_id) do update set title=excluded.title,start_time=excluded.start_time,end_time=excluded.end_time,event_type=excluded.event_type,location_name=excluded.location_name,location_address=excluded.location_address,organization_id=excluded.organization_id,facility_id=excluded.facility_id,status=excluded.status,updated_at=now() returning id into v_event;
 -- Roster fan-out/family display is a later reviewed slice. No fictitious participants.
 return v_event;
end $$;
create function rink_private.request_ice(p_facility uuid,p_area uuid,p_org uuid,p_team uuid,p_start timestamptz,p_end timestamptz,p_note text,p_slot uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_slot public.open_slots;
begin
 if not rink_private.renter(p_org) or public.current_person_id() is null then raise exception 'Organization scheduling permission required'; end if;
 if not exists(select 1 from public.facilities where id=p_facility and is_active and workspace_id is not null) or not exists(select 1 from public.facility_areas where id=p_area and facility_id=p_facility and is_active and area_type='ice') then raise exception 'Invalid ice area'; end if;
 if p_team is not null and not exists(select 1 from public.teams where id=p_team and organization_id=p_org and is_active) then raise exception 'Team does not belong to organization'; end if;
 if p_start is null or p_end is null or p_start<=now() or p_end<=p_start or p_end-p_start>interval '24 hours' then raise exception 'Choose a valid future time'; end if;
 if p_slot is not null then
 select * into v_slot from public.open_slots where id=p_slot for update;
 if not found or v_slot.status<>'open' or not v_slot.is_public or v_slot.facility_id<>p_facility or v_slot.area_id<>p_area or v_slot.start_time<>p_start or v_slot.end_time<>p_end then raise exception 'Opening is no longer available'; end if;
 end if;
 if exists(select 1 from public.bookings where area_id=p_area and status in ('confirmed','maintenance') and start_time<p_end and end_time>p_start) then raise exception 'Ice is already reserved'; end if;
 if p_slot is null and exists(select 1 from public.open_slots where area_id=p_area and status='open' and start_time<p_end and end_time>p_start) then raise exception 'Request the published opening instead'; end if;
 insert into public.open_slot_requests(open_slot_id,facility_id,area_id,organization_id,team_id,start_time,end_time,requested_by_person_id,note) values(p_slot,p_facility,p_area,p_org,p_team,p_start,p_end,public.current_person_id(),nullif(trim(p_note),'')) returning id into v_id;
 return v_id;
end $$;
create function rink_private.award(p_request uuid,p_amount numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.open_slot_requests; s public.open_slots; v_booking uuid;
begin
 -- Consistent lock order: slot first (when present), then area, then request.
 select * into r from public.open_slot_requests where id=p_request;
 if not found or not rink_private.scheduler(r.facility_id) then raise exception 'Rink scheduling permission required'; end if;
 if r.open_slot_id is not null then
 select * into s from public.open_slots where id=r.open_slot_id for update;
 if s.status<>'open' then raise exception 'Opening already closed'; end if;
 end if;
 perform 1 from public.facility_areas where id=r.area_id for update;
 select * into r from public.open_slot_requests where id=p_request for update;
 if r.status<>'requested' or r.start_time<=now() then raise exception 'Request is no longer available'; end if;
 if not rink_private.renter(r.organization_id) and not exists(select 1 from public.organizations where id=r.organization_id and workspace_id is not null) then raise exception 'Organization unavailable'; end if;
 if r.open_slot_id is null and exists(select 1 from public.open_slots where area_id=r.area_id and status='open' and start_time<r.end_time and end_time>r.start_time) then raise exception 'Request the released opening instead'; end if;
 if p_amount is null or p_amount<0 then raise exception 'A nonnegative agreed price is required'; end if;
 if r.open_slot_id is not null and p_amount is distinct from s.price then raise exception 'Award price must match published opening'; end if;
 insert into public.bookings(facility_id,area_id,booking_type,title,organization_id,team_id,start_time,end_time,amount,status) values(r.facility_id,r.area_id,case when r.team_id is null then 'organization_rental' else 'team_rental' end,'Ice reservation',r.organization_id,r.team_id,r.start_time,r.end_time,p_amount,'confirmed') returning id into v_booking;
 update public.open_slot_requests set status='awarded',awarded_booking_id=v_booking,decided_at=now() where id=r.id;
 -- Close every other pending request that competes for this ice (published opening or new time).
 update public.open_slot_requests set status='closed',decided_at=now() where area_id=r.area_id and id<>r.id and status='requested' and start_time<r.end_time and end_time>r.start_time;
 if r.open_slot_id is not null then
 update public.open_slots set status='awarded',awarded_booking_id=v_booking where id=r.open_slot_id;
 update public.open_slot_requests set status='closed',decided_at=now() where open_slot_id=r.open_slot_id and id<>r.id and status='requested';
 update public.open_slot_offers set status='suppressed' where open_slot_id=r.open_slot_id and status='queued';
 end if;
 perform rink_private.publish_booking(v_booking);
 return v_booking;
end $$;
create function rink_private.request_cancel(p_booking uuid,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.bookings; v_id uuid;
begin
 select * into b from public.bookings where id=p_booking for update;
 if not found or not rink_private.renter(b.organization_id) then raise exception 'Organization scheduling permission required'; end if;
 if b.status<>'confirmed' or b.start_time<=now() then raise exception 'Only future confirmed bookings can be cancelled'; end if;
 insert into public.booking_cancellation_requests(booking_id,requested_by_person_id,reason,policy_snapshot) values(b.id,public.current_person_id(),trim(p_reason),(select to_jsonb(p) from public.facility_policies p where p.facility_id=b.facility_id)) returning id into v_id;
 return v_id;
end $$;
create function rink_private.decide_cancel(p_request uuid,p_approve boolean,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.booking_cancellation_requests; b public.bookings; v_slot uuid;
begin
 select * into c from public.booking_cancellation_requests where id=p_request for update;
 select * into b from public.bookings where id=c.booking_id for update;
 if c.id is null or not rink_private.scheduler(b.facility_id) then raise exception 'Rink scheduling permission required'; end if;
 if c.status<>'pending' or b.status<>'confirmed' or b.start_time<=now() or p_approve is null then raise exception 'Request is no longer pending'; end if;
 update public.booking_cancellation_requests set status=case when p_approve then 'approved' else 'denied' end,decided_by_person_id=public.current_person_id(),decided_at=now(),decision_note=left(p_note,1000) where id=c.id;
 if p_approve then
 update public.bookings set status='cancelled',updated_at=now() where id=b.id;
 insert into public.open_slots(facility_id,area_id,source_booking_id,source,start_time,end_time,price,status,is_public,cancellation_request_id,released_by_person_id,released_at) values(b.facility_id,b.area_id,b.id,'cancellation',b.start_time,b.end_time,b.amount,'open',true,c.id,public.current_person_id(),now()) returning id into v_slot;
 insert into public.booking_financial_dispositions(booking_id,cancellation_request_id,status) values(b.id,c.id,'undetermined');
 -- No delivery provider is configured. Log truthful no-channel outcomes only.
 insert into public.open_slot_offers(open_slot_id,waitlist_id,person_id,channel,status)
 select v_slot,w.id,w.contact_person_id,'none','no_channel' from public.facility_waitlist w
 where w.facility_id=b.facility_id and w.active and w.notify_opt_in and w.organization_id is distinct from b.organization_id
 and exists(select 1 from public.organizations o join public.workspace_members m on m.workspace_id=o.workspace_id join public.workspace_roles r on r.workspace_id=m.workspace_id and r.person_id=m.person_id where o.id=w.organization_id and m.person_id=w.contact_person_id and m.status='active' and r.role in ('owner','admin')) on conflict do nothing;
 perform rink_private.publish_booking(b.id);
 end if;
 return v_slot;
end $$;
create function rink_private.waitlist(p_facility uuid,p_org uuid,p_opt_in boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not rink_private.renter(p_org) or public.current_person_id() is null then raise exception 'Organization scheduling permission required'; end if;
 if not exists(select 1 from public.facilities where id=p_facility and is_active and workspace_id is not null) then raise exception 'Facility unavailable'; end if;
 insert into public.facility_waitlist(facility_id,organization_id,contact_person_id,notify_opt_in) values(p_facility,p_org,public.current_person_id(),coalesce(p_opt_in,false)) on conflict(facility_id,organization_id,contact_person_id) do update set notify_opt_in=excluded.notify_opt_in returning id into v_id;
 return v_id;
end $$;
create function rink_private.decline_request(p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.open_slot_requests;
begin
 select * into r from public.open_slot_requests where id=p_request for update;
 if not found or not rink_private.scheduler(r.facility_id) then raise exception 'Rink scheduling permission required'; end if;
 if r.status<>'requested' then raise exception 'Request is no longer pending'; end if;
 update public.open_slot_requests set status='closed',decided_at=now() where id=r.id;
 return r.id;
end $$;
create function rink_private.withdraw_request(p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.open_slot_requests;
begin
 select * into r from public.open_slot_requests where id=p_request for update;
 if not found or not rink_private.renter(r.organization_id) then raise exception 'Organization scheduling permission required'; end if;
 if r.status<>'requested' then raise exception 'Request is no longer pending'; end if;
 update public.open_slot_requests set status='withdrawn',decided_at=now() where id=r.id;
 return r.id;
end $$;
-- Browser-facing wrappers are invokers. Privileged implementation lives in a
-- non-REST schema, authenticates membership and returns only defined fields.
create function public.public_facility_calendar(p_slug text,p_from timestamptz,p_to timestamptz) returns jsonb language sql security invoker set search_path='' as $$select rink_private.public_calendar(p_slug,p_from,p_to)$$;
create function public.public_open_slots(p_slug text) returns jsonb language sql security invoker set search_path='' as $$select rink_private.public_slots(p_slug)$$;
create function public.rink_catalog() returns jsonb language sql security invoker set search_path='' as $$select rink_private.catalog()$$;
create function public.rink_workspace() returns jsonb language sql security invoker set search_path='' as $$select rink_private.workspace()$$;
create function public.request_rink_ice(p_facility uuid,p_area uuid,p_org uuid,p_team uuid,p_start timestamptz,p_end timestamptz,p_note text,p_slot uuid default null) returns uuid language sql security invoker set search_path='' as $$select rink_private.request_ice(p_facility,p_area,p_org,p_team,p_start,p_end,p_note,p_slot)$$;
create function public.award_open_slot(p_request uuid,p_amount numeric) returns uuid language sql security invoker set search_path='' as $$select rink_private.award(p_request,p_amount)$$;
create function public.request_booking_cancellation(p_booking uuid,p_reason text) returns uuid language sql security invoker set search_path='' as $$select rink_private.request_cancel(p_booking,p_reason)$$;
create function public.decide_cancellation(p_request uuid,p_approve boolean,p_note text) returns uuid language sql security invoker set search_path='' as $$select rink_private.decide_cancel(p_request,p_approve,p_note)$$;
create function public.decline_rink_request(p_request uuid) returns uuid language sql security invoker set search_path='' as $$select rink_private.decline_request(p_request)$$;
create function public.withdraw_rink_request(p_request uuid) returns uuid language sql security invoker set search_path='' as $$select rink_private.withdraw_request(p_request)$$;
create function public.set_facility_waitlist(p_facility uuid,p_org uuid,p_opt_in boolean) returns uuid language sql security invoker set search_path='' as $$select rink_private.waitlist(p_facility,p_org,p_opt_in)$$;
revoke all on all functions in schema rink_private from public,anon,authenticated;
grant execute on function rink_private.public_calendar(text,timestamptz,timestamptz),rink_private.public_slots(text),rink_private.catalog() to anon,authenticated;
grant execute on function rink_private.workspace(),rink_private.request_ice(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),rink_private.award(uuid,numeric),rink_private.request_cancel(uuid,text),rink_private.decide_cancel(uuid,boolean,text),rink_private.waitlist(uuid,uuid,boolean),rink_private.decline_request(uuid),rink_private.withdraw_request(uuid) to authenticated;
revoke all on function public.public_facility_calendar(text,timestamptz,timestamptz),public.public_open_slots(text),public.rink_catalog(),public.rink_workspace(),public.request_rink_ice(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),public.award_open_slot(uuid,numeric),public.request_booking_cancellation(uuid,text),public.decide_cancellation(uuid,boolean,text),public.set_facility_waitlist(uuid,uuid,boolean),public.decline_rink_request(uuid),public.withdraw_rink_request(uuid) from public,anon,authenticated;
grant execute on function public.public_facility_calendar(text,timestamptz,timestamptz),public.public_open_slots(text),public.rink_catalog() to anon,authenticated;
grant execute on function public.rink_workspace(),public.request_rink_ice(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,uuid),public.award_open_slot(uuid,numeric),public.request_booking_cancellation(uuid,text),public.decide_cancellation(uuid,boolean,text),public.set_facility_waitlist(uuid,uuid,boolean),public.decline_rink_request(uuid),public.withdraw_rink_request(uuid) to authenticated;
commit;

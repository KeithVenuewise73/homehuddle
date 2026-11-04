-- NEW LEAD -> instant alert.
-- Wrapped in an exception guard so an alert failure can NEVER block lead capture.
create or replace function public.trg_leads_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.enqueue_internal_alert(
      'lead',
      'lead:' || new.id::text,
      'NEW LEAD - ' || coalesce(new.platform_interest, 'Venuewise') || E'\n'
        || coalesce(new.name, 'Unknown')
        || case when new.organization_name is not null then ' (' || new.organization_name || ')' else '' end
        || E'\n' || coalesce(new.role, 'role n/a')
        || E'\nCall: ' || coalesce(new.phone, 'no phone')
        || E'\n' || coalesce(new.email, 'no email')
    );
  exception when others then
    null; -- swallow: never break the insert
  end;
  return new;
end;
$$;

drop trigger if exists leads_alert on public.leads;
create trigger leads_alert
  after insert on public.leads
  for each row execute function public.trg_leads_alert();


-- NEW BOOKING -> instant alert (revenue event).
create or replace function public.trg_bookings_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.enqueue_internal_alert(
      'booking',
      'booking:' || new.id::text,
      'NEW BOOKING - $' || coalesce(new.amount, 0)::text || E'\n'
        || coalesce(new.customer_name, 'Unknown')
        || E'\n' || coalesce(new.booking_type, 'rental')
        || E'\n' || to_char(new.start_time, 'Mon DD HH12:MI AM')
        || E'\nCall: ' || coalesce(new.contact_phone, 'no phone')
    );
  exception when others then
    null;
  end;
  return new;
end;
$$;

drop trigger if exists bookings_alert on public.bookings;
create trigger bookings_alert
  after insert on public.bookings
  for each row execute function public.trg_bookings_alert();
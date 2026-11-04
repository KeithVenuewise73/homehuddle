-- Anyone who SHOULD be receiving texts but isn't. Catches silent drop-off.
create or replace view public.sms_delivery_health as
select
  fm.family_id,
  fm.name,
  fm.role,
  fm.phone,
  fm.sms_status,
  fm.person_id is not null as linked,
  (select max(o.sent_at) from public.sms_outbox o where o.phone = fm.phone) as last_received,
  extract(day from now() - (select max(o.sent_at) from public.sms_outbox o where o.phone = fm.phone))::int as days_silent,
  case
    when fm.person_id is null                     then 'UNLINKED - no person record'
    when fm.sms_status = 'none'                   then 'NO CONSENT REQUEST SENT'
    when fm.sms_status = 'pending'                then 'CONSENT NEVER CONFIRMED'
    when (select max(o.sent_at) from public.sms_outbox o where o.phone = fm.phone) is null
                                                  then 'NEVER RECEIVED ANYTHING'
    when (select max(o.sent_at) from public.sms_outbox o where o.phone = fm.phone)
           < now() - interval '10 days'           then 'WENT SILENT'
    else 'ok'
  end as health
from public.family_members fm
where coalesce(fm.receives_sms, true) = true;

-- Fold delivery problems into the existing 9am text so they surface daily.
create or replace function public.escalate_stale_leads()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stale integer; v_oldest integer; v_broken integer; v_msg text;
begin
  select count(*), coalesce(max(extract(day from now() - created_at))::int, 0)
    into v_stale, v_oldest
  from public.leads
  where status = 'new' and not is_spam and created_at < now() - interval '24 hours';

  select count(*) into v_broken
  from public.sms_delivery_health where health <> 'ok';

  if v_stale = 0 and v_broken = 0 then return 0; end if;

  v_msg := 'HOMEHUDDLE DAILY';
  if v_stale > 0 then
    v_msg := v_msg || E'\nUnworked leads: ' || v_stale::text
             || ' (oldest ' || v_oldest::text || 'd)';
  end if;
  if v_broken > 0 then
    v_msg := v_msg || E'\nMembers not receiving texts: ' || v_broken::text;
  end if;

  perform public.enqueue_internal_alert('lead', 'daily:' || current_date::text, v_msg);
  return v_stale + v_broken;
end;
$$;
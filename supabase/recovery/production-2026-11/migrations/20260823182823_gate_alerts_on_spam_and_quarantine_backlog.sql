-- Alerts fire only for leads that survive the spam check.
create or replace function public.trg_leads_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_spam then
    return new;
  end if;
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
    null;
  end;
  return new;
end;
$$;

-- Retro-score the existing 20 so the daily digest doesn't send you after bots.
update public.leads
set is_spam = true,
    spam_reason = public.score_lead_spam(name, email, phone, organization_name),
    status = 'spam'
where public.score_lead_spam(name, email, phone, organization_name) is not null;

-- Stale digest counts only real, unworked leads.
create or replace function public.escalate_stale_leads()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_stale integer; v_oldest integer;
begin
  select count(*), coalesce(max(extract(day from now() - created_at))::int, 0)
    into v_stale, v_oldest
  from public.leads
  where status = 'new' and not is_spam and created_at < now() - interval '24 hours';

  if v_stale = 0 then return 0; end if;

  perform public.enqueue_internal_alert(
    'lead', 'stale-digest:' || current_date::text,
    'UNWORKED LEADS: ' || v_stale::text
      || E'\nOldest is ' || v_oldest::text || ' days cold.'
  );
  return v_stale;
end;
$$;
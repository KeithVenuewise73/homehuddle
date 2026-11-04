-- You average ~2 real leads/month. A burst is definitionally not organic.
-- Blocks volume attacks even when the content looks clean.
create or replace function public.trg_leads_rate_limit()
returns trigger
language plpgsql
as $$
declare
  v_recent integer;
  v_dupe   integer;
begin
  select count(*) into v_recent
  from public.leads
  where created_at > now() - interval '1 hour';

  if v_recent >= 5 then
    insert into public.blocked_submissions (source_table, reason, payload)
    values ('leads', 'rate_limit_hourly', to_jsonb(new));
    return null;
  end if;

  -- Same email OR same phone inside 24h = resubmission or bot loop.
  select count(*) into v_dupe
  from public.leads
  where created_at > now() - interval '24 hours'
    and (
      (new.email is not null and lower(email) = lower(new.email))
      or (new.phone is not null and regexp_replace(phone,'[^0-9]','','g')
            = regexp_replace(new.phone,'[^0-9]','','g'))
    );

  if v_dupe >= 1 then
    insert into public.blocked_submissions (source_table, reason, payload)
    values ('leads', 'duplicate_24h', to_jsonb(new));
    return null;
  end if;

  return new;
end;
$$;

drop trigger if exists leads_rate_limit on public.leads;
-- Runs before the spam check (alphabetical order on same-timing triggers).
create trigger leads_rate_limit
  before insert on public.leads
  for each row execute function public.trg_leads_rate_limit();
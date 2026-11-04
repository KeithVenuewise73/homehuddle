alter table public.leads add column if not exists is_spam boolean not null default false;
alter table public.leads add column if not exists spam_reason text;

-- Scores a lead against the patterns actually observed in this table.
create or replace function public.score_lead_spam(
  p_name text, p_email text, p_phone text, p_org text
) returns text
language plpgsql
immutable
as $$
declare
  v_local text;
  v_area  text;
begin
  -- Gmail dot-abuse: 4+ periods in the local part is not a real address people type.
  v_local := split_part(coalesce(p_email,''), '@', 1);
  if (length(v_local) - length(replace(v_local, '.', ''))) >= 4 then
    return 'gmail_dot_abuse';
  end if;

  -- Random-string names: internal caps runs, no vowel rhythm.
  if p_name ~ '[a-z][A-Z]{2}' or p_name ~ '[A-Z]{4}' then
    return 'random_case_name';
  end if;
  if coalesce(p_org,'') ~ '[a-z][A-Z]{2}' or coalesce(p_org,'') ~ '[A-Z]{4}' then
    return 'random_case_org';
  end if;

  -- Impossible North American area codes (NANP: first digit 2-9, second digit not 9-in-11 style N11).
  v_area := left(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'), 3);
  if length(v_area) = 3 then
    if left(v_area,1) in ('0','1') or v_area ~ '^\d11$' then
      return 'invalid_area_code';
    end if;
  end if;

  return null;
end;
$$;

create or replace function public.trg_leads_spam_check()
returns trigger
language plpgsql
as $$
declare v_reason text;
begin
  v_reason := public.score_lead_spam(new.name, new.email, new.phone, new.organization_name);
  if v_reason is not null then
    new.is_spam := true;
    new.spam_reason := v_reason;
    new.status := 'spam';
  end if;
  return new;
end;
$$;

drop trigger if exists leads_spam_check on public.leads;
create trigger leads_spam_check
  before insert on public.leads
  for each row execute function public.trg_leads_spam_check();
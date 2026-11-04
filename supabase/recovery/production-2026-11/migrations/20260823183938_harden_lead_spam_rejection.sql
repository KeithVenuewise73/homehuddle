-- Audit trail so a false positive is never silently lost.
create table if not exists public.blocked_submissions (
  id uuid primary key default gen_random_uuid(),
  source_table text not null,
  reason text not null,
  payload jsonb not null,
  blocked_at timestamptz not null default now()
);
alter table public.blocked_submissions enable row level security;
-- service_role only.

-- Refined scoring. Deliberately avoids the all-caps false positive:
-- "JOHN SMITH" must never be flagged. Only lowercase->UPPER transitions count.
create or replace function public.score_lead_spam(
  p_name text, p_email text, p_phone text, p_org text
) returns text
language plpgsql
immutable
as $$
declare
  v_local text;
  v_area  text;
  v_word  text;
begin
  v_local := split_part(coalesce(p_email,''), '@', 1);
  if (length(v_local) - length(replace(v_local, '.', ''))) >= 4 then
    return 'gmail_dot_abuse';
  end if;

  -- Mixed-case randomness only (lowercase immediately followed by 2+ capitals).
  -- All-caps and Title Case names are safe.
  if p_name ~ '[a-z][A-Z]{2}' then
    return 'random_case_name';
  end if;
  if coalesce(p_org,'') ~ '[a-z][A-Z]{2}' then
    return 'random_case_org';
  end if;

  -- A name word with 6+ letters and no vowel is not a human name.
  foreach v_word in array regexp_split_to_array(coalesce(p_name,''), '\s+') loop
    if length(v_word) >= 6 and v_word !~* '[aeiouy]' then
      return 'no_vowels';
    end if;
  end loop;

  v_area := left(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'), 3);
  if length(v_area) = 3 and (left(v_area,1) in ('0','1') or v_area ~ '^\d11$') then
    return 'invalid_area_code';
  end if;

  return null;
end;
$$;

-- Now REJECT instead of merely flagging, but archive the payload first.
create or replace function public.trg_leads_spam_check()
returns trigger
language plpgsql
as $$
declare v_reason text;
begin
  v_reason := public.score_lead_spam(new.name, new.email, new.phone, new.organization_name);
  if v_reason is not null then
    insert into public.blocked_submissions (source_table, reason, payload)
    values ('leads', v_reason, to_jsonb(new));
    return null;  -- silently drop; the bot gets a success-looking response
  end if;
  return new;
end;
$$;
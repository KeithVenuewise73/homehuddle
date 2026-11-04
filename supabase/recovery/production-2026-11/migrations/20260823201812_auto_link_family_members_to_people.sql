-- Root cause: a family_member with no person_id is invisible to the nightly digest.
-- Find-or-create the person by phone on insert/update so this can't recur.
create or replace function public.trg_family_member_link_person()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_person uuid;
  v_phone  text;
begin
  if new.person_id is not null or new.phone is null or btrim(new.phone) = '' then
    return new;
  end if;

  -- Normalise to E.164 for US 10/11-digit input.
  v_phone := regexp_replace(new.phone, '[^0-9]', '', 'g');
  if length(v_phone) = 10 then
    v_phone := '+1' || v_phone;
  elsif length(v_phone) = 11 and left(v_phone,1) = '1' then
    v_phone := '+' || v_phone;
  else
    v_phone := new.phone;
  end if;

  select id into v_person from public.people where phone = v_phone limit 1;

  if v_person is null then
    insert into public.people (phone, display_name, sms_opt_in, phone_verified)
    values (v_phone, new.name, coalesce(new.receives_sms, true), false)
    returning id into v_person;
  end if;

  new.person_id := v_person;
  new.phone     := v_phone;
  return new;
end;
$$;

drop trigger if exists family_member_link_person on public.family_members;
create trigger family_member_link_person
  before insert or update of phone, person_id on public.family_members
  for each row execute function public.trg_family_member_link_person();

-- Prevent the same person being added twice to one family.
create unique index if not exists family_members_family_person_uniq
  on public.family_members (family_id, person_id) where person_id is not null;
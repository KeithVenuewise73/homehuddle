-- invite_family_member accepts 'grandparent' but family_access_role_check rejected it.
alter table public.family_access drop constraint family_access_role_check;
alter table public.family_access add constraint family_access_role_check
  check (role = any (array['owner','parent','grandparent','viewer','player']));

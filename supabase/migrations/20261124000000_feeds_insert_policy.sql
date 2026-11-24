-- Allow signed-in family members to add feeds (teams / iCal calendars) for their own family.
-- Before this, feeds had SELECT and UPDATE policies only, so every INSERT was rejected by RLS.
create policy auth_feeds_insert on public.feeds
  for insert to authenticated
  with check (email in (select current_family_emails()));

do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'organization_events_organization_id_fkey'
      and table_schema = 'public'
  ) then
    alter table public.organization_events
      add constraint organization_events_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete cascade;
  end if;
end $$;
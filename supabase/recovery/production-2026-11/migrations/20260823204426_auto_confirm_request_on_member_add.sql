-- Any member added later — dashboard, future UI, import — gets the same request.
-- AFTER INSERT so the row exists for queue_member_confirmation to read.
create or replace function public.trg_family_member_request_consent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.phone is null or btrim(new.phone) = '' then return new; end if;
  if coalesce(new.receives_sms, true) = false     then return new; end if;
  if coalesce(new.sms_status, 'none') <> 'none'   then return new; end if;

  begin
    perform public.queue_member_confirmation(new.id, null);
  exception when others then
    null;  -- never block the insert
  end;
  return new;
end;
$$;

drop trigger if exists family_member_request_consent on public.family_members;
create trigger family_member_request_consent
  after insert on public.family_members
  for each row execute function public.trg_family_member_request_consent();
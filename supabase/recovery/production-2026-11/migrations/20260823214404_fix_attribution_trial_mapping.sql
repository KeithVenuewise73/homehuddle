-- The live subscription is status='trialing' with trial_end = NULL, so keying
-- trial_started_at off trial_end alone would have reported 0 trials forever
-- while trials were actually running. Treat status='trialing' as the trial
-- signal too.
create or replace function public.sync_attribution_from_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    update public.signup_attribution sa
       set trial_started_at = coalesce(
             sa.trial_started_at,
             case when NEW.trial_end is not null or NEW.status = 'trialing'
                  then NEW.created_at end),
           converted_at = coalesce(
             sa.converted_at,
             case when NEW.status = 'active' then now() end),
           is_founder = sa.is_founder or coalesce(NEW.founder, false)
     where sa.family_id = NEW.family_id;
  exception when others then
    null;
  end;
  return NEW;
end;
$$;
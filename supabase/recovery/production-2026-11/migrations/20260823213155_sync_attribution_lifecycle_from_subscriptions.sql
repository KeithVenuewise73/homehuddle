-- creative_funnel reads trials = count(trial_started_at) and paid = count(converted_at)
-- on signup_attribution. Nothing wrote those columns, so both would read 0 forever
-- even once attribution rows exist. subscriptions is the real source of truth, so
-- mirror it across instead of asking the frontend to guess.
--
-- Mapping (deliberate, so it can be argued with):
--   trial_started_at <- subscription created_at, when the subscription carries a trial_end
--   converted_at     <- the moment status first becomes 'active'
--   is_founder       <- subscriptions.founder (authoritative; never invented at signup)
--
-- Guarded per repo convention: an attribution-sync failure must never block a
-- subscription insert/update, because that is the billing path.

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
             case when NEW.trial_end is not null then NEW.created_at end),
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

drop trigger if exists subscriptions_sync_attribution on public.subscriptions;
create trigger subscriptions_sync_attribution
  after insert or update of status, founder, trial_end on public.subscriptions
  for each row execute function public.sync_attribution_from_subscription();

comment on function public.sync_attribution_from_subscription() is
  'Mirrors subscription lifecycle onto signup_attribution so creative_funnel can report trials/paid. Exception-guarded: never blocks the billing write.';
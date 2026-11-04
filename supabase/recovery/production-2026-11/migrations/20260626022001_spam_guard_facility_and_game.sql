
-- Extend honeypot + guard to the two remaining public forms.
ALTER TABLE public.facility_spotlight_submissions ADD COLUMN IF NOT EXISTS hp_field text;
ALTER TABLE public.game_coverage_tips            ADD COLUMN IF NOT EXISTS hp_field text;

-- Recreate the guard fn to also recognize facility_name for the gibberish backstop.
CREATE OR REPLACE FUNCTION public.reject_spam_submission()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $fn$
DECLARE
  j jsonb := to_jsonb(NEW);
  nm text;
  hp text;
  midcaps int;
BEGIN
  hp := j->>'hp_field';
  IF hp IS NOT NULL AND length(btrim(hp)) > 0 THEN
    RETURN NULL;
  END IF;

  nm := coalesce(j->>'athlete_name', j->>'coach_name', j->>'team_name',
                 j->>'organization_name', j->>'nominee_name', j->>'facility_name', '');
  IF nm <> '' AND nm !~ '\s' AND length(nm) >= 14 THEN
    midcaps := length(substr(nm,2)) - length(regexp_replace(substr(nm,2), '[A-Z]', '', 'g'));
    IF midcaps >= 3 THEN
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_reject_spam ON public.facility_spotlight_submissions;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.facility_spotlight_submissions
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();
DROP TRIGGER IF EXISTS trg_reject_spam ON public.game_coverage_tips;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.game_coverage_tips
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();

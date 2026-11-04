
-- Honeypot column: a hidden form field humans never see/fill; bots fill everything.
ALTER TABLE public.athlete_spotlight_submissions      ADD COLUMN IF NOT EXISTS hp_field text;
ALTER TABLE public.coach_spotlight_submissions        ADD COLUMN IF NOT EXISTS hp_field text;
ALTER TABLE public.team_spotlight_submissions         ADD COLUMN IF NOT EXISTS hp_field text;
ALTER TABLE public.organization_spotlight_submissions ADD COLUMN IF NOT EXISTS hp_field text;
ALTER TABLE public.legends_spotlight_submissions      ADD COLUMN IF NOT EXISTS hp_field text;

-- Guard function: silently drops obvious spam (returns NULL = row not inserted, no error to tip off bots).
CREATE OR REPLACE FUNCTION public.reject_spam_submission()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $fn$
DECLARE
  j jsonb := to_jsonb(NEW);
  nm text;
  hp text;
  midcaps int;
BEGIN
  -- 1) Honeypot: if the hidden field is filled, it's a bot.
  hp := j->>'hp_field';
  IF hp IS NOT NULL AND length(btrim(hp)) > 0 THEN
    RETURN NULL;
  END IF;

  -- 2) Gibberish-name backstop (works right now, no form change needed):
  --    a single long token, no spaces, with several mid-word capitals = random string.
  nm := coalesce(j->>'athlete_name', j->>'coach_name', j->>'team_name',
                 j->>'organization_name', j->>'nominee_name', '');
  IF nm <> '' AND nm !~ '\s' AND length(nm) >= 14 THEN
    midcaps := length(substr(nm,2)) - length(regexp_replace(substr(nm,2), '[A-Z]', '', 'g'));
    IF midcaps >= 3 THEN
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_reject_spam ON public.athlete_spotlight_submissions;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.athlete_spotlight_submissions
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();
DROP TRIGGER IF EXISTS trg_reject_spam ON public.coach_spotlight_submissions;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.coach_spotlight_submissions
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();
DROP TRIGGER IF EXISTS trg_reject_spam ON public.team_spotlight_submissions;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.team_spotlight_submissions
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();
DROP TRIGGER IF EXISTS trg_reject_spam ON public.organization_spotlight_submissions;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.organization_spotlight_submissions
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();
DROP TRIGGER IF EXISTS trg_reject_spam ON public.legends_spotlight_submissions;
CREATE TRIGGER trg_reject_spam BEFORE INSERT ON public.legends_spotlight_submissions
  FOR EACH ROW EXECUTE FUNCTION public.reject_spam_submission();

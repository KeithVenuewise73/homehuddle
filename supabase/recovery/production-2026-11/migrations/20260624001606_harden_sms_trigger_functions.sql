-- Trigger functions should never be callable directly as PostgREST RPCs.
-- They only run from their AFTER INSERT/UPDATE triggers; revoke direct EXECUTE.
REVOKE ALL ON FUNCTION public.trg_family_events_sms() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.trg_events_sms()        FROM public, anon, authenticated;
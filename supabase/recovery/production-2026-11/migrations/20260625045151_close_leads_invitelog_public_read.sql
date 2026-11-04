
-- Remove public READ on leads and invite_log (inserts stay open for capture forms).
-- Reads should be admin/service-role only, not exposed to the browser anon key.
drop policy if exists "anon_read_leads" on public.leads;
drop policy if exists "read own invite log" on public.invite_log;

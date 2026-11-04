-- HARDENING, from the Supabase security advisors run against this build.
--
-- 1. Postgres grants EXECUTE to PUBLIC on every new function, so `GRANT ... TO
--    authenticated` did NOT stop `anon` reaching the admin functions. They each
--    check is_admin() and raise 42501, so nothing was exposed -- but a grant
--    that is never meant to be used should not exist. Revoke it explicitly.
--
-- 2. Eight helper functions had a role-mutable search_path. Two of them are
--    trigger functions that run inside SECURITY DEFINER writes, which is
--    exactly where a mutable search_path is worth closing.

-- ── 1. admin surface: authenticated only ───────────────────────────────────
REVOKE ALL ON FUNCTION public.gametracker_import(jsonb, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_update_live(uuid, text, integer, integer, text, text, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_event_admin(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_admin_events(text, date, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_save_source(text, text, text, text, boolean, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_sources() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_link_alias(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.gametracker_delete_event(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.gametracker_import(jsonb, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_update_live(uuid, text, integer, integer, text, text, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_event_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_admin_events(text, date, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_save_source(text, text, text, text, boolean, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_sources() TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_link_alias(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_delete_event(uuid) TO authenticated;

-- The four public read functions stay reachable by anon on purpose -- they are
-- the public API, and they return only events from published sources.
REVOKE ALL ON FUNCTION public.gametracker_events(text,text,text,text,text,text,text,text,date,date,date,integer,text,integer,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gametracker_event(uuid)            FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gametracker_filters(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gametracker_school(text, integer)  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.gametracker_events(text,text,text,text,text,text,text,text,date,date,date,integer,text,integer,integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_event(uuid)            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_filters(text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gametracker_school(text, integer)  TO anon, authenticated;

-- ── 2. pin search_path on the helpers and triggers ─────────────────────────
ALTER FUNCTION gametracker.norm_text(text)         SET search_path = 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.norm_school(text)       SET search_path = 'gametracker', 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.slugify(text)           SET search_path = 'gametracker', 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.norm_status(text)       SET search_path = 'gametracker', 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.parse_time(text)        SET search_path = 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.tg_events_derive()      SET search_path = 'gametracker', 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.tg_events_emit()        SET search_path = 'gametracker', 'pg_catalog', 'public', 'pg_temp';
ALTER FUNCTION gametracker.tg_touch()              SET search_path = 'pg_catalog', 'public', 'pg_temp';
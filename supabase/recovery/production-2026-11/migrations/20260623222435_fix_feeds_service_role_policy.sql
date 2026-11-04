-- "Service role full access" was roles={public} ALL using(true) — i.e. EVERYONE
-- (anon + authenticated) had full access to all feeds. Replace it with a policy
-- actually scoped to the service_role, so the owner-scoped auth_feeds_* policies
-- are the real gate for logged-in users.
DROP POLICY IF EXISTS "Service role full access" ON public.feeds;

CREATE POLICY feeds_service_role_all ON public.feeds
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);
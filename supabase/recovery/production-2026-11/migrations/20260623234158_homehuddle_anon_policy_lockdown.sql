-- ============================================================================
-- HomeHuddle anon-policy lockdown (Stage 4)
-- Removes all anon/public "using=true / with_check=true" policies on the six
-- family data tables. The logged-in calendar uses ONLY the authenticated
-- session (verified: every sb.from read/write is covered by an auth_* policy),
-- and the sync function runs as service_role (bypasses RLS), so this does not
-- affect the live app. It DOES retire the old anon-based join.html signup until
-- that flow is migrated to authenticated. Authenticated auth_* policies and the
-- feeds service_role policy are intentionally kept.
-- ============================================================================

-- families
DROP POLICY IF EXISTS "Allow public insert on families" ON public.families;
DROP POLICY IF EXISTS "anon_insert_families"            ON public.families;
DROP POLICY IF EXISTS "Allow public select on families" ON public.families;
DROP POLICY IF EXISTS "anon_read_families"              ON public.families;
DROP POLICY IF EXISTS "anon_update_families"            ON public.families;
DROP POLICY IF EXISTS "families_own_access"             ON public.families; -- public ALL, auth.uid()=id : meaningless, drop as cleanup

-- family_events
DROP POLICY IF EXISTS "Allow public delete on family_events" ON public.family_events;
DROP POLICY IF EXISTS "anon_delete_family_events"            ON public.family_events;
DROP POLICY IF EXISTS "Allow public insert on family_events" ON public.family_events;
DROP POLICY IF EXISTS "anon_insert_family_events"            ON public.family_events;
DROP POLICY IF EXISTS "Allow public select on family_events" ON public.family_events;
DROP POLICY IF EXISTS "anon_read_family_events"              ON public.family_events;
DROP POLICY IF EXISTS "Allow public update on family_events" ON public.family_events;

-- family_members
DROP POLICY IF EXISTS "Allow public insert on family_members" ON public.family_members;
DROP POLICY IF EXISTS "anon_insert_members"                   ON public.family_members;
DROP POLICY IF EXISTS "Allow public select on family_members" ON public.family_members;
DROP POLICY IF EXISTS "anon_read_members"                     ON public.family_members;
DROP POLICY IF EXISTS "anon_update_members"                   ON public.family_members;

-- feeds  (keep auth_feeds_select, auth_feeds_update, feeds_service_role_all)
DROP POLICY IF EXISTS "Public can insert feeds"  ON public.feeds;
DROP POLICY IF EXISTS "anon_insert_feeds"        ON public.feeds;
DROP POLICY IF EXISTS "Public can read own feeds" ON public.feeds;
DROP POLICY IF EXISTS "anon_read_feeds"          ON public.feeds;
DROP POLICY IF EXISTS "anon_update_feeds"        ON public.feeds;

-- reminders  (keep auth_reminders_select, auth_reminders_update)
DROP POLICY IF EXISTS "anon_insert_reminders" ON public.reminders;
DROP POLICY IF EXISTS "anon_read_reminders"   ON public.reminders;
DROP POLICY IF EXISTS "anon_update_reminders" ON public.reminders;

-- push_subscriptions  (keep auth_push_select, auth_push_insert, auth_push_update)
DROP POLICY IF EXISTS "delete push subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "anon_insert_push_subs"     ON public.push_subscriptions;
DROP POLICY IF EXISTS "insert push subscription"  ON public.push_subscriptions;
DROP POLICY IF EXISTS "anon_read_push_subs"       ON public.push_subscriptions;
DROP POLICY IF EXISTS "read push subscriptions"   ON public.push_subscriptions;
DROP POLICY IF EXISTS "anon_update_push_subs"     ON public.push_subscriptions;
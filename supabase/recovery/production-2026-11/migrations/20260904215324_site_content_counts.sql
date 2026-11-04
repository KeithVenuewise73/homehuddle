-- One call that answers "what does this site actually have?", so a page can
-- decide what to show instead of announcing sections that are empty.
--
-- This is the rule the GameTracker modules already follow -- render only when
-- there is something real -- generalized to the rest of the site. A section
-- that appears the day its first item is published, and not before, needs no
-- maintenance and can never advertise something that is not there.
CREATE OR REPLACE FUNCTION public.site_content_counts()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'gametracker', 'pg_temp'
AS $$
  SELECT jsonb_build_object(
    'games',      (SELECT count(*) FROM gametracker.events e
                    JOIN gametracker.sources s ON s.key = e.source WHERE s.publish),
    'games_today',(SELECT count(*) FROM gametracker.events e
                    JOIN gametracker.sources s ON s.key = e.source
                   WHERE s.publish
                     AND e.event_date = (now() AT TIME ZONE 'America/New_York')::date),
    'articles',            (SELECT count(*) FROM public.articles       WHERE published),
    'spotlights_athlete',  (SELECT count(*) FROM public.spotlights
                             WHERE published AND spotlight_type = 'Athlete'),
    'spotlights_coach',    (SELECT count(*) FROM public.spotlights
                             WHERE published AND spotlight_type = 'Coach'),
    'spotlights_team',     (SELECT count(*) FROM public.spotlights
                             WHERE published AND spotlight_type = 'Team'),
    'spotlights',          (SELECT count(*) FROM public.spotlights     WHERE published),
    'legends',             (SELECT count(*) FROM public.legends        WHERE published),
    'organizations',       (SELECT count(*) FROM public.organizations  WHERE published),
    'podcast',             (SELECT count(*) FROM public.podcast_episodes
                             WHERE coalesce(status, 'draft') = 'published'),
    'videos',              (SELECT count(*) FROM public.videos),
    'galleries',           (SELECT count(*) FROM public.photo_galleries),
    'sponsors',            (SELECT count(*) FROM public.sponsors       WHERE active)
  );
$$;

REVOKE ALL ON FUNCTION public.site_content_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_content_counts() TO anon, authenticated;
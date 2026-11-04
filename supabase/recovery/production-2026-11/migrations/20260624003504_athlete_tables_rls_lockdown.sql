-- ============================================================================
-- Lock down AthleteHuddle / 5-Star athlete tables (MINORS' personal data).
-- These were RLS-DISABLED and wide open. Existing policies were broken
-- (compared auth.uid() to families.id). Replace with family_access-scoped
-- policies. Public exposure ONLY for explicitly is_public rows (spotlight).
-- ============================================================================

-- ---------- athletes ----------
ALTER TABLE public.athletes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS athletes_family_access ON public.athletes;
DROP POLICY IF EXISTS athletes_public_read   ON public.athletes;

CREATE POLICY athletes_auth_select ON public.athletes
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(false)));
CREATE POLICY athletes_auth_insert ON public.athletes
  FOR INSERT TO authenticated
  WITH CHECK (family_id IN (SELECT public.current_family_ids(true)));
CREATE POLICY athletes_auth_update ON public.athletes
  FOR UPDATE TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(true)))
  WITH CHECK (family_id IN (SELECT public.current_family_ids(true)));
CREATE POLICY athletes_auth_delete ON public.athletes
  FOR DELETE TO authenticated
  USING (family_id IN (SELECT public.current_family_ids(true)));
-- deliberate public spotlight read (5-Star), only when a parent has opted the athlete public
CREATE POLICY athletes_public_read ON public.athletes
  FOR SELECT TO anon, authenticated
  USING (is_public = true);
CREATE POLICY athletes_service_all ON public.athletes
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ---------- athlete_player_links (HomeHuddle player <-> athlete bridge) ----------
ALTER TABLE public.athlete_player_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS athlete_player_links_access ON public.athlete_player_links;
CREATE POLICY apl_auth_select ON public.athlete_player_links
  FOR SELECT TO authenticated
  USING (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(false))));
CREATE POLICY apl_auth_write ON public.athlete_player_links
  FOR ALL TO authenticated
  USING (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(true))))
  WITH CHECK (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(true))));
CREATE POLICY apl_service_all ON public.athlete_player_links
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ---------- child detail tables: sports / stats / goals / events ----------
-- (private to the family; spotlight-specific public reads added when we build 5-Star)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['athlete_sports','athlete_stats','athlete_goals','athlete_events'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', t||'_access', t);
    EXECUTE format($f$
      CREATE POLICY %I ON public.%I FOR SELECT TO authenticated
      USING (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(false))));
    $f$, t||'_auth_select', t);
    EXECUTE format($f$
      CREATE POLICY %I ON public.%I FOR ALL TO authenticated
      USING (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(true))))
      WITH CHECK (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(true))));
    $f$, t||'_auth_write', t);
    EXECUTE format($f$
      CREATE POLICY %I ON public.%I FOR ALL TO service_role USING (true) WITH CHECK (true);
    $f$, t||'_service_all', t);
  END LOOP;
END $$;

-- ---------- athlete_videos (has its own per-video is_public) ----------
ALTER TABLE public.athlete_videos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS athlete_videos_access ON public.athlete_videos;
-- keep existing athlete_videos_public_read (is_public = true)
CREATE POLICY athlete_videos_auth_select ON public.athlete_videos
  FOR SELECT TO authenticated
  USING (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(false))));
CREATE POLICY athlete_videos_auth_write ON public.athlete_videos
  FOR ALL TO authenticated
  USING (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(true))))
  WITH CHECK (athlete_id IN (SELECT id FROM public.athletes WHERE family_id IN (SELECT public.current_family_ids(true))));
CREATE POLICY athlete_videos_service_all ON public.athlete_videos
  FOR ALL TO service_role USING (true) WITH CHECK (true);
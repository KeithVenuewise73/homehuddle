-- Step 5 — the merged calendar.
-- For the logged-in person (auth.uid()), return every event across ALL the
-- families they have ACTIVE access to, as one list, tagged by family so the
-- UI can color-code. A parent in one family gets one family's events; a
-- grandparent in three gets all three merged — SAME code path. That's the
-- "one rendering engine, no special mode" design from the data model.
--
-- SECURITY DEFINER + explicit auth.uid() filter so it is correct and safe
-- even before the Phase 4 RLS rewrite on family_events. A caller only ever
-- sees families they are actively linked to; a stranger sees nothing.

CREATE OR REPLACE FUNCTION public.get_merged_calendar(
    p_from timestamptz DEFAULT NULL,
    p_to   timestamptz DEFAULT NULL
)
RETURNS TABLE (
    event_id    uuid,
    family_id   uuid,
    family_name text,
    title       text,
    event_start timestamptz,
    event_end   timestamptz,
    location    text,
    category    text,
    visibility  text,
    my_role     text,
    can_edit    boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
    SELECT
        e.id, e.family_id, f.family_name, e.title,
        e.event_start, e.event_end, e.location, e.category, e.visibility,
        fa.role, fa.can_edit
    FROM public.family_access fa
    JOIN public.people        p ON p.id = fa.person_id
    JOIN public.families      f ON f.id = fa.family_id
    JOIN public.family_events e ON e.family_id = fa.family_id
    WHERE p.auth_user_id = auth.uid()
      AND fa.status = 'active'
      AND (p_from IS NULL OR e.event_start >= p_from)
      AND (p_to   IS NULL OR e.event_start <  p_to)
    ORDER BY e.event_start;
$$;

REVOKE ALL ON FUNCTION public.get_merged_calendar(timestamptz, timestamptz) FROM public;
GRANT EXECUTE ON FUNCTION public.get_merged_calendar(timestamptz, timestamptz) TO authenticated;

COMMENT ON FUNCTION public.get_merged_calendar(timestamptz, timestamptz) IS
  'Returns the logged-in person''s events merged across all their active families, tagged by family + role. One code path for parents (1 family) and grandparents (many).';
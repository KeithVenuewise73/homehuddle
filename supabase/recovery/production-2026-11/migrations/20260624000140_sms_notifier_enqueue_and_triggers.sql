-- ============================================================================
-- SMS notifier — Stage B: enqueue helper + change-detecting triggers
-- ============================================================================

-- Fan one change out to every eligible recipient of a family, once.
CREATE OR REPLACE FUNCTION public.enqueue_sms_for_family(
  p_family_id    uuid,
  p_actor_person uuid,
  p_event_ref    text,
  p_change_hash  text,
  p_message      text
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.sms_outbox (person_id, phone, family_id, event_ref, change_hash, message, status)
  SELECT p.id, p.phone, p_family_id, p_event_ref, p_change_hash, p_message, 'pending'
  FROM public.family_access fa
  JOIN public.people p ON p.id = fa.person_id
  WHERE fa.family_id = p_family_id
    AND fa.status = 'active'
    AND p.phone_verified = true
    AND coalesce(p.sms_opt_in, true) = true
    AND p.phone IS NOT NULL
    AND (p_actor_person IS NULL OR p.id <> p_actor_person)
  ON CONFLICT ON CONSTRAINT sms_outbox_dedup DO NOTHING;
$$;

-- ---- family_events (manual) -------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_family_events_sms()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_hash text;
  v_old_hash text;
  v_actor    uuid;
  v_famname  text;
  v_msg      text;
  v_when     text;
BEGIN
  -- only notify for events that start in the future
  IF NEW.event_start IS NULL OR NEW.event_start <= now() THEN
    RETURN NEW;
  END IF;

  v_new_hash := md5(
    coalesce(NEW.title,'') || '|' || coalesce(NEW.event_start::text,'') || '|' ||
    coalesce(NEW.event_end::text,'') || '|' || coalesce(NEW.location,'')
  );

  IF TG_OP = 'UPDATE' THEN
    v_old_hash := md5(
      coalesce(OLD.title,'') || '|' || coalesce(OLD.event_start::text,'') || '|' ||
      coalesce(OLD.event_end::text,'') || '|' || coalesce(OLD.location,'')
    );
    IF v_old_hash = v_new_hash THEN
      RETURN NEW;  -- nothing notify-worthy changed
    END IF;
  END IF;

  -- the person who made the change (manual edits run under the user's session)
  SELECT id INTO v_actor FROM public.people WHERE auth_user_id = auth.uid() LIMIT 1;

  SELECT family_name INTO v_famname FROM public.families WHERE id = NEW.family_id;
  v_when := to_char(NEW.event_start AT TIME ZONE 'America/New_York', 'Dy Mon FMDD at FMHH12:MI AM');
  v_msg := coalesce(v_famname,'HomeHuddle') || ' — ' ||
           (CASE WHEN TG_OP = 'INSERT' THEN 'New event: ' ELSE 'Updated: ' END) ||
           coalesce(NEW.title,'event') || ' ' || v_when;

  PERFORM public.enqueue_sms_for_family(
    NEW.family_id, v_actor, 'fe:' || NEW.id::text, v_new_hash, v_msg
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS family_events_sms ON public.family_events;
CREATE TRIGGER family_events_sms
  AFTER INSERT OR UPDATE ON public.family_events
  FOR EACH ROW EXECUTE FUNCTION public.trg_family_events_sms();

-- ---- events (synced sports schedule) ---------------------------------------
CREATE OR REPLACE FUNCTION public.trg_events_sms()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_hash text;
  v_old_hash text;
  v_family   uuid;
  v_famname  text;
  v_ref      text;
  v_msg      text;
  v_when     text;
BEGIN
  -- future events only; ignore rows flagged duplicate
  IF NEW."start" IS NULL OR NEW."start" <= now() OR coalesce(NEW.is_duplicate,false) THEN
    RETURN NEW;
  END IF;

  v_new_hash := md5(
    coalesce(NEW.name,'') || '|' || coalesce(NEW."start"::text,'') || '|' ||
    coalesce(NEW."end"::text,'') || '|' || coalesce(NEW.location,'')
  );

  IF TG_OP = 'UPDATE' THEN
    v_old_hash := md5(
      coalesce(OLD.name,'') || '|' || coalesce(OLD."start"::text,'') || '|' ||
      coalesce(OLD."end"::text,'') || '|' || coalesce(OLD.location,'')
    );
    IF v_old_hash = v_new_hash THEN
      RETURN NEW;
    END IF;
  END IF;

  -- resolve the owning family via the feed's email
  SELECT fam.id, fam.family_name INTO v_family, v_famname
  FROM public.feeds f
  JOIN public.families fam ON fam.email = f.email
  WHERE f.id = NEW.feed_id
  LIMIT 1;

  IF v_family IS NULL THEN
    RETURN NEW;  -- can't attribute to a family; skip
  END IF;

  -- LOGICAL identity (resilient to volatile feed UIDs): family + name + date
  v_ref := 'ev:' || v_family::text || ':' ||
           md5(lower(coalesce(NEW.name,'')) || '|' ||
               to_char(NEW."start" AT TIME ZONE 'America/New_York','YYYY-MM-DD'));

  v_when := to_char(NEW."start" AT TIME ZONE 'America/New_York', 'Dy Mon FMDD at FMHH12:MI AM');
  v_msg := coalesce(v_famname,'HomeHuddle') || ' — ' ||
           (CASE WHEN TG_OP = 'INSERT' THEN 'New: ' ELSE 'Schedule change: ' END) ||
           coalesce(NEW.name,'event') || ' ' || v_when;

  PERFORM public.enqueue_sms_for_family(v_family, NULL, v_ref, v_new_hash, v_msg);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_sms ON public.events;
CREATE TRIGGER events_sms
  AFTER INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.trg_events_sms();

-- helper is internal-only
REVOKE ALL ON FUNCTION public.enqueue_sms_for_family(uuid,uuid,text,text,text) FROM public, anon, authenticated;
-- ============================================================================
-- SMS notifier — Stage A: schema
-- people.sms_opt_in : default-on opt-out flag (honor STOP later)
-- sms_outbox        : one row per (person, logical-event, change) = send-once.
--   The UNIQUE(person_id, event_ref, change_hash) is the dedup guarantee:
--   re-syncing the same change can never enqueue a second time.
-- ============================================================================
ALTER TABLE public.people
  ADD COLUMN IF NOT EXISTS sms_opt_in boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.sms_outbox (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id    uuid NOT NULL,
  phone        text NOT NULL,
  family_id    uuid,
  event_ref    text NOT NULL,         -- logical event identity (resilient to volatile feed UIDs)
  change_hash  text NOT NULL,         -- hash of the notify-worthy fields (time/location/title)
  message      text NOT NULL,
  status       text NOT NULL DEFAULT 'pending',  -- pending | sent | failed | skipped
  attempts     int  NOT NULL DEFAULT 0,
  error        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  sent_at      timestamptz,
  CONSTRAINT sms_outbox_dedup UNIQUE (person_id, event_ref, change_hash)
);

CREATE INDEX IF NOT EXISTS sms_outbox_status_idx ON public.sms_outbox (status, created_at);

-- Lock it down: no anon/authenticated access; only service_role (sender) touches it.
ALTER TABLE public.sms_outbox ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sms_outbox_service_all ON public.sms_outbox;
CREATE POLICY sms_outbox_service_all ON public.sms_outbox
  FOR ALL TO service_role USING (true) WITH CHECK (true);
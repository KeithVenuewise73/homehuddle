-- Phase 2 Step 1 — Person-centric identity foundation
-- Creates people + family_access (+ family_members.person_id), RLS enabled.

-- 1) people
CREATE TABLE IF NOT EXISTS public.people (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           text        NOT NULL UNIQUE,
    phone_verified  boolean     NOT NULL DEFAULT false,
    auth_user_id    uuid        UNIQUE REFERENCES auth.users (id) ON DELETE SET NULL,
    display_name    text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT people_phone_e164_chk CHECK (phone ~ '^\+[1-9]\d{6,14}$')
);

COMMENT ON TABLE  public.people                IS 'Individuals who can log in. Identity anchored on a verified phone number.';
COMMENT ON COLUMN public.people.phone          IS 'E.164 format (+17165551234). UNIQUE. Identity anchor + Twilio channel.';
COMMENT ON COLUMN public.people.phone_verified IS 'TRUE only after SMS (Twilio Verify) succeeds. Gate for real login.';
COMMENT ON COLUMN public.people.auth_user_id   IS 'Links to auth.users — the real Supabase session owner.';

-- 2) family_access
CREATE TABLE IF NOT EXISTS public.family_access (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id   uuid        NOT NULL REFERENCES public.people   (id) ON DELETE CASCADE,
    family_id   uuid        NOT NULL REFERENCES public.families (id) ON DELETE CASCADE,
    role        text        NOT NULL CHECK (role   IN ('owner','parent','viewer','player')),
    status      text        NOT NULL DEFAULT 'active' CHECK (status IN ('active','pending','revoked')),
    can_edit    boolean     NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT family_access_person_family_uq UNIQUE (person_id, family_id)
);

COMMENT ON TABLE  public.family_access        IS 'Bridge between people and families. Sharing happens at the family/household level.';
COMMENT ON COLUMN public.family_access.role   IS 'owner / parent / viewer / player. Kids default to player + can_edit=false.';
COMMENT ON COLUMN public.family_access.status IS 'active / pending / revoked. Only active rows grant access (used by RLS later).';

CREATE INDEX IF NOT EXISTS family_access_family_id_idx ON public.family_access (family_id);
CREATE INDEX IF NOT EXISTS family_access_person_id_idx ON public.family_access (person_id);

-- 3) family_members.person_id
ALTER TABLE public.family_members
    ADD COLUMN IF NOT EXISTS person_id uuid REFERENCES public.people (id) ON DELETE SET NULL;

COMMENT ON COLUMN public.family_members.person_id IS 'Links this roster entry to a real, verified person (people.id). NULL until they verify.';

CREATE INDEX IF NOT EXISTS family_members_person_id_idx ON public.family_members (person_id);

-- 4) RLS — enabled from birth, self-read only. No write policies yet (Step 2 writes via elevated function).
ALTER TABLE public.people        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS people_self_select ON public.people;
CREATE POLICY people_self_select ON public.people
    FOR SELECT TO authenticated
    USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS family_access_self_select ON public.family_access;
CREATE POLICY family_access_self_select ON public.family_access
    FOR SELECT TO authenticated
    USING (person_id IN (SELECT id FROM public.people WHERE auth_user_id = auth.uid()));
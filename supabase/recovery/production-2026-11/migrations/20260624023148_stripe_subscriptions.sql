-- Stripe subscription tracking
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id            uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  stripe_customer_id   text UNIQUE,
  stripe_subscription_id text UNIQUE,
  stripe_price_id      text,
  status               text NOT NULL DEFAULT 'incomplete'
                         CHECK (status IN ('trialing','active','past_due','canceled','incomplete','paused')),
  trial_end            timestamptz,
  current_period_end   timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Family members can read their own subscription status
CREATE POLICY "sub_select_own_family" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT current_family_ids(false)));

-- Only service_role writes (webhook updates this)
CREATE POLICY "sub_service_role_all" ON public.subscriptions
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.trg_subscriptions_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.trg_subscriptions_updated_at();

-- Index for fast family lookups
CREATE INDEX IF NOT EXISTS idx_subscriptions_family_id ON public.subscriptions(family_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_customer ON public.subscriptions(stripe_customer_id);

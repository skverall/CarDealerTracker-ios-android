CREATE TABLE IF NOT EXISTS public.dealer_referral_pending_purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invited_user_id UUID NOT NULL,
    event_id TEXT NOT NULL UNIQUE,
    event_type TEXT,
    period_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referral_pending_invited_user_id ON public.dealer_referral_pending_purchases(invited_user_id);

ALTER TABLE public.dealer_referral_pending_purchases ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.dealer_referral_pending_purchases FROM authenticated;

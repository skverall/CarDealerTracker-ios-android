CREATE TABLE IF NOT EXISTS public.dealer_referral_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    code TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_dealer_referral_codes_dealer_id ON public.dealer_referral_codes(dealer_id);

CREATE TABLE IF NOT EXISTS public.dealer_referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    referrer_dealer_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    referrer_user_id UUID NOT NULL,
    invited_user_id UUID NOT NULL UNIQUE,
    invited_dealer_id UUID,
    reward_status TEXT NOT NULL DEFAULT 'pending',
    reward_event_id TEXT,
    reward_months INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reward_granted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_dealer_referrals_referrer_dealer_id ON public.dealer_referrals(referrer_dealer_id);
CREATE INDEX IF NOT EXISTS idx_dealer_referrals_invited_user_id ON public.dealer_referrals(invited_user_id);

CREATE TABLE IF NOT EXISTS public.dealer_referral_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_dealer_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    referrer_user_id UUID NOT NULL,
    invited_user_id UUID NOT NULL,
    reward_months INT NOT NULL DEFAULT 1,
    event_id TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dealer_referral_rewards_referrer_user_id ON public.dealer_referral_rewards(referrer_user_id);

CREATE TABLE IF NOT EXISTS public.referral_bonus_access (
    user_id UUID PRIMARY KEY,
    bonus_access_until TIMESTAMPTZ NOT NULL,
    total_months INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.dealer_referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dealer_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dealer_referral_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_bonus_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "dealer_referral_codes_select" ON public.dealer_referral_codes;
CREATE POLICY "dealer_referral_codes_select" ON public.dealer_referral_codes FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "dealer_referral_codes_insert" ON public.dealer_referral_codes;
CREATE POLICY "dealer_referral_codes_insert" ON public.dealer_referral_codes FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "dealer_referral_codes_update" ON public.dealer_referral_codes;
CREATE POLICY "dealer_referral_codes_update" ON public.dealer_referral_codes FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "dealer_referrals_select" ON public.dealer_referrals;
CREATE POLICY "dealer_referrals_select" ON public.dealer_referrals FOR SELECT
    USING (
        auth.uid() = invited_user_id
        OR auth.uid() = referrer_user_id
        OR crm_can_access(referrer_dealer_id)
    );

DROP POLICY IF EXISTS "dealer_referrals_insert" ON public.dealer_referrals;
CREATE POLICY "dealer_referrals_insert" ON public.dealer_referrals FOR INSERT
    WITH CHECK (auth.uid() = invited_user_id);

DROP POLICY IF EXISTS "dealer_referral_rewards_select" ON public.dealer_referral_rewards;
CREATE POLICY "dealer_referral_rewards_select" ON public.dealer_referral_rewards FOR SELECT
    USING (auth.uid() = referrer_user_id OR crm_can_access(referrer_dealer_id));

DROP POLICY IF EXISTS "referral_bonus_access_select" ON public.referral_bonus_access;
CREATE POLICY "referral_bonus_access_select" ON public.referral_bonus_access FOR SELECT
    USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE ON public.dealer_referral_codes TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.dealer_referrals TO authenticated;
GRANT SELECT ON public.dealer_referral_rewards TO authenticated;
GRANT SELECT ON public.referral_bonus_access TO authenticated;

DROP FUNCTION IF EXISTS public.get_or_create_dealer_referral_code(uuid);
CREATE OR REPLACE FUNCTION public.get_or_create_dealer_referral_code(p_dealer_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_code text;
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    IF NOT crm_can_access(p_dealer_id) THEN
        RAISE EXCEPTION 'Forbidden';
    END IF;

    SELECT code INTO v_code
    FROM public.dealer_referral_codes
    WHERE dealer_id = p_dealer_id
      AND is_active = true
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_code IS NULL THEN
        LOOP
            v_code := upper(encode(gen_random_bytes(4), 'hex'));
            EXIT WHEN NOT EXISTS (
                SELECT 1 FROM public.dealer_referral_codes WHERE code = v_code
            );
        END LOOP;

        INSERT INTO public.dealer_referral_codes (dealer_id, code, created_by)
        VALUES (p_dealer_id, v_code, v_uid);
    END IF;

    RETURN v_code;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_or_create_dealer_referral_code(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.claim_dealer_referral(text);
CREATE OR REPLACE FUNCTION public.claim_dealer_referral(p_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_ref dealer_referral_codes%rowtype;
    v_invited_org uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    IF p_code IS NULL OR btrim(p_code) = '' THEN
        RAISE EXCEPTION 'Invalid code';
    END IF;

    SELECT * INTO v_ref
    FROM public.dealer_referral_codes
    WHERE code = upper(btrim(p_code))
      AND is_active = true
    LIMIT 1;

    IF v_ref.id IS NULL THEN
        RAISE EXCEPTION 'Invalid code';
    END IF;

    IF v_ref.created_by = v_uid THEN
        RAISE EXCEPTION 'Self referral not allowed';
    END IF;

    IF EXISTS (SELECT 1 FROM public.dealer_referrals WHERE invited_user_id = v_uid) THEN
        RETURN false;
    END IF;

    SELECT id INTO v_invited_org
    FROM public.organizations
    WHERE id = v_uid
    LIMIT 1;

    INSERT INTO public.dealer_referrals (
        code,
        referrer_dealer_id,
        referrer_user_id,
        invited_user_id,
        invited_dealer_id
    ) VALUES (
        v_ref.code,
        v_ref.dealer_id,
        v_ref.created_by,
        v_uid,
        v_invited_org
    );

    UPDATE public.dealer_referral_codes
    SET last_used_at = now()
    WHERE id = v_ref.id;

    RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.claim_dealer_referral(text) TO authenticated;

DROP FUNCTION IF EXISTS public.process_referral_reward(uuid, text, text, text);
CREATE OR REPLACE FUNCTION public.process_referral_reward(
    p_invited_user_id uuid,
    p_event_id text,
    p_event_type text,
    p_period_type text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_ref dealer_referrals%rowtype;
    v_now timestamptz := now();
    v_base timestamptz;
BEGIN
    IF p_invited_user_id IS NULL THEN
        RETURN false;
    END IF;

    IF p_event_type IS NULL THEN
        RETURN false;
    END IF;

    IF upper(p_period_type) = 'TRIAL' THEN
        RETURN false;
    END IF;

    IF upper(p_event_type) NOT IN ('INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE') THEN
        RETURN false;
    END IF;

    IF p_event_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.dealer_referral_rewards WHERE event_id = p_event_id
    ) THEN
        RETURN false;
    END IF;

    SELECT * INTO v_ref
    FROM public.dealer_referrals
    WHERE invited_user_id = p_invited_user_id
      AND reward_status = 'pending'
    LIMIT 1
    FOR UPDATE;

    IF v_ref.id IS NULL THEN
        RETURN false;
    END IF;

    UPDATE public.dealer_referrals
    SET reward_status = 'granted',
        reward_granted_at = v_now,
        reward_event_id = p_event_id
    WHERE id = v_ref.id;

    INSERT INTO public.dealer_referral_rewards (
        referrer_dealer_id,
        referrer_user_id,
        invited_user_id,
        reward_months,
        event_id
    ) VALUES (
        v_ref.referrer_dealer_id,
        v_ref.referrer_user_id,
        v_ref.invited_user_id,
        v_ref.reward_months,
        p_event_id
    );

    SELECT bonus_access_until INTO v_base
    FROM public.referral_bonus_access
    WHERE user_id = v_ref.referrer_user_id;

    IF v_base IS NULL OR v_base < v_now THEN
        v_base := v_now;
    END IF;

    INSERT INTO public.referral_bonus_access (user_id, bonus_access_until, total_months, updated_at)
    VALUES (v_ref.referrer_user_id, v_base + interval '1 month', 1, v_now)
    ON CONFLICT (user_id) DO UPDATE
    SET bonus_access_until = EXCLUDED.bonus_access_until,
        total_months = public.referral_bonus_access.total_months + 1,
        updated_at = v_now;

    RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.process_referral_reward(uuid, text, text, text) TO authenticated;

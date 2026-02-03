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
    v_event text := upper(coalesce(p_event_type, ''));
    v_period text := upper(coalesce(p_period_type, ''));
BEGIN
    IF p_invited_user_id IS NULL THEN
        RETURN false;
    END IF;

    IF v_event = '' THEN
        RETURN false;
    END IF;

    IF v_period = 'TRIAL' THEN
        RETURN false;
    END IF;

    IF v_event NOT IN ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE') THEN
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

REVOKE EXECUTE ON FUNCTION public.process_referral_reward(uuid, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_reward(uuid, text, text, text) TO service_role;

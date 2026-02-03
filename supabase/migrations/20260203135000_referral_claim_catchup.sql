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
    v_pending record;
    v_rewarded boolean := false;
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

    SELECT event_id, event_type, period_type
    INTO v_pending
    FROM public.dealer_referral_pending_purchases
    WHERE invited_user_id = v_uid
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_pending.event_id IS NOT NULL THEN
        v_rewarded := public.process_referral_reward(
            v_uid,
            v_pending.event_id,
            v_pending.event_type,
            v_pending.period_type
        );
        IF v_rewarded THEN
            DELETE FROM public.dealer_referral_pending_purchases
            WHERE invited_user_id = v_uid;
        END IF;
    END IF;

    RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.claim_dealer_referral(text) TO authenticated;

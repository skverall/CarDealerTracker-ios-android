DROP FUNCTION IF EXISTS public.get_referral_stats();
CREATE OR REPLACE FUNCTION public.get_referral_stats()
RETURNS TABLE(
    total_rewards int,
    last_rewarded_at timestamptz,
    bonus_access_until timestamptz,
    total_months int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    RETURN QUERY
    SELECT
        (SELECT count(*)::int FROM public.dealer_referral_rewards WHERE referrer_user_id = v_uid),
        (SELECT max(created_at) FROM public.dealer_referral_rewards WHERE referrer_user_id = v_uid),
        (SELECT bonus_access_until FROM public.referral_bonus_access WHERE user_id = v_uid),
        COALESCE((SELECT total_months FROM public.referral_bonus_access WHERE user_id = v_uid), 0);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_referral_stats() TO authenticated;

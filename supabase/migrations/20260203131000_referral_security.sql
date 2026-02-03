REVOKE EXECUTE ON FUNCTION public.process_referral_reward(uuid, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_reward(uuid, text, text, text) TO service_role;

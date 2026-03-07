CREATE SCHEMA IF NOT EXISTS extensions;

ALTER EXTENSION moddatetime
    SET SCHEMA extensions;

DROP POLICY IF EXISTS "No direct API access" ON crm.cars;
CREATE POLICY "No direct API access"
ON crm.cars
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "No direct API access" ON public.audit_logs;
CREATE POLICY "No direct API access"
ON public.audit_logs
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "No direct API access" ON public.dealer_referral_pending_purchases;
CREATE POLICY "No direct API access"
ON public.dealer_referral_pending_purchases
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "No direct API access" ON public.team_invite_code_attempts;
CREATE POLICY "No direct API access"
ON public.team_invite_code_attempts
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "No direct API access" ON public.team_invite_codes;
CREATE POLICY "No direct API access"
ON public.team_invite_codes
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

DROP POLICY IF EXISTS "No direct API access" ON public.user_favorites;
CREATE POLICY "No direct API access"
ON public.user_favorites
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

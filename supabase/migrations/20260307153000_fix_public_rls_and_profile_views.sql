ALTER VIEW IF EXISTS public.safe_profiles
    SET (security_invoker = true);

ALTER VIEW IF EXISTS public.public_profiles
    SET (security_invoker = true);

ALTER TABLE public.team_invite_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_invite_code_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vin_checks ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.team_invite_codes FROM anon, authenticated;
REVOKE ALL ON TABLE public.team_invite_code_attempts FROM anon, authenticated;
REVOKE ALL ON TABLE public.user_favorites FROM anon, authenticated;
REVOKE ALL ON TABLE public.vin_checks FROM anon, authenticated;

DROP POLICY IF EXISTS "Public can submit vin checks" ON public.vin_checks;

CREATE POLICY "Public can submit vin checks"
ON public.vin_checks
FOR INSERT
TO anon, authenticated
WITH CHECK (
    nullif(btrim(name), '') IS NOT NULL
    AND nullif(btrim(whatsapp), '') IS NOT NULL
    AND nullif(btrim(vin), '') IS NOT NULL
    AND coalesce(status, 'pending') = 'pending'
);

GRANT INSERT ON TABLE public.vin_checks TO anon, authenticated;

CREATE TABLE IF NOT EXISTS public.team_invite_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    invitation_token text NOT NULL UNIQUE,
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    invite_code text NOT NULL UNIQUE CHECK (invite_code ~ '^[A-Z0-9]{6,10}$'),
    invited_email text,
    max_uses integer NOT NULL DEFAULT 1 CHECK (max_uses > 0 AND max_uses <= 100),
    used_count integer NOT NULL DEFAULT 0 CHECK (used_count >= 0 AND used_count <= max_uses),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz
);

CREATE INDEX IF NOT EXISTS team_invite_codes_org_idx
    ON public.team_invite_codes (organization_id);

CREATE INDEX IF NOT EXISTS team_invite_codes_expires_idx
    ON public.team_invite_codes (expires_at);

CREATE TABLE IF NOT EXISTS public.team_invite_code_attempts (
    id bigserial PRIMARY KEY,
    user_id uuid,
    invite_code text NOT NULL,
    success boolean NOT NULL DEFAULT false,
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS team_invite_code_attempts_user_code_idx
    ON public.team_invite_code_attempts (user_id, invite_code, created_at DESC);

CREATE INDEX IF NOT EXISTS team_invite_code_attempts_code_idx
    ON public.team_invite_code_attempts (invite_code, created_at DESC);

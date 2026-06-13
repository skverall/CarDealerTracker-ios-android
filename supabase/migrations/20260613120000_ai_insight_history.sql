CREATE TABLE IF NOT EXISTS public.ai_insight_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    requested_by uuid NOT NULL,
    period text NOT NULL CHECK (period IN ('today', 'week', 'month', 'threeMonths', 'sixMonths', 'all')),
    range_start date,
    range_end date,
    fingerprint text NOT NULL,
    language text,
    currency_code text,
    region text,
    summary text NOT NULL,
    insights jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(insights) = 'array'),
    recommendations jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(recommendations) = 'array'),
    source_counts jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(source_counts) = 'object'),
    request_metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(request_metadata) = 'object'),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_insight_reports_org_period_created_idx
    ON public.ai_insight_reports (organization_id, period, created_at DESC);

CREATE INDEX IF NOT EXISTS ai_insight_reports_org_period_fingerprint_idx
    ON public.ai_insight_reports (organization_id, period, fingerprint, created_at DESC);

CREATE INDEX IF NOT EXISTS ai_insight_reports_requested_by_created_idx
    ON public.ai_insight_reports (requested_by, created_at DESC);

ALTER TABLE public.ai_insight_reports ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.ai_insight_reports FROM anon, authenticated;
GRANT ALL ON TABLE public.ai_insight_reports TO service_role;

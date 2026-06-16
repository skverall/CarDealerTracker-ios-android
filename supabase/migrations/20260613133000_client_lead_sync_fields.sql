ALTER TABLE crm.dealer_clients
    ADD COLUMN IF NOT EXISTS lead_stage text DEFAULT 'new',
    ADD COLUMN IF NOT EXISTS lead_source text,
    ADD COLUMN IF NOT EXISTS assigned_user_id uuid,
    ADD COLUMN IF NOT EXISTS estimated_value numeric,
    ADD COLUMN IF NOT EXISTS priority integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS lead_created_at timestamptz,
    ADD COLUMN IF NOT EXISTS last_contact_at timestamptz,
    ADD COLUMN IF NOT EXISTS next_follow_up_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_crm_dealer_clients_lead_stage
    ON crm.dealer_clients (dealer_id, lead_stage);

CREATE INDEX IF NOT EXISTS idx_crm_dealer_clients_assigned_user
    ON crm.dealer_clients (dealer_id, assigned_user_id);

CREATE OR REPLACE VIEW public.crm_dealer_clients AS
SELECT * FROM crm.dealer_clients;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_dealer_clients TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_clients(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    result_record public.crm_dealer_clients%ROWTYPE;
    results jsonb := '[]'::jsonb;
    v_dealer_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_dealer_id := (item->>'dealer_id')::uuid;
        PERFORM public.assert_crm_access(v_dealer_id);

        INSERT INTO public.crm_dealer_clients (
            id,
            dealer_id,
            name,
            phone,
            email,
            notes,
            request_details,
            preferred_date,
            created_at,
            updated_at,
            deleted_at,
            status,
            vehicle_id,
            lead_stage,
            lead_source,
            assigned_user_id,
            estimated_value,
            priority,
            lead_created_at,
            last_contact_at,
            next_follow_up_at
        )
        VALUES (
            (item->>'id')::uuid,
            v_dealer_id,
            item->>'name',
            item->>'phone',
            item->>'email',
            item->>'notes',
            item->>'request_details',
            (item->>'preferred_date')::timestamptz,
            (item->>'created_at')::timestamptz,
            (item->>'updated_at')::timestamptz,
            (item->>'deleted_at')::timestamptz,
            item->>'status',
            (item->>'vehicle_id')::uuid,
            COALESCE(NULLIF(item->>'lead_stage', ''), 'new'),
            NULLIF(item->>'lead_source', ''),
            NULLIF(item->>'assigned_user_id', '')::uuid,
            NULLIF(item->>'estimated_value', '')::numeric,
            COALESCE(NULLIF(item->>'priority', '')::integer, 0),
            NULLIF(item->>'lead_created_at', '')::timestamptz,
            NULLIF(item->>'last_contact_at', '')::timestamptz,
            NULLIF(item->>'next_follow_up_at', '')::timestamptz
        )
        ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name,
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            notes = EXCLUDED.notes,
            request_details = EXCLUDED.request_details,
            preferred_date = EXCLUDED.preferred_date,
            updated_at = EXCLUDED.updated_at,
            deleted_at = EXCLUDED.deleted_at,
            status = EXCLUDED.status,
            vehicle_id = EXCLUDED.vehicle_id,
            lead_stage = CASE
                WHEN item ? 'lead_stage' THEN COALESCE(NULLIF(item->>'lead_stage', ''), 'new')
                ELSE public.crm_dealer_clients.lead_stage
            END,
            lead_source = CASE
                WHEN item ? 'lead_source' THEN NULLIF(item->>'lead_source', '')
                ELSE public.crm_dealer_clients.lead_source
            END,
            assigned_user_id = CASE
                WHEN item ? 'assigned_user_id' THEN NULLIF(item->>'assigned_user_id', '')::uuid
                ELSE public.crm_dealer_clients.assigned_user_id
            END,
            estimated_value = CASE
                WHEN item ? 'estimated_value' THEN NULLIF(item->>'estimated_value', '')::numeric
                ELSE public.crm_dealer_clients.estimated_value
            END,
            priority = CASE
                WHEN item ? 'priority' THEN COALESCE(NULLIF(item->>'priority', '')::integer, 0)
                ELSE public.crm_dealer_clients.priority
            END,
            lead_created_at = CASE
                WHEN item ? 'lead_created_at' THEN NULLIF(item->>'lead_created_at', '')::timestamptz
                ELSE public.crm_dealer_clients.lead_created_at
            END,
            last_contact_at = CASE
                WHEN item ? 'last_contact_at' THEN NULLIF(item->>'last_contact_at', '')::timestamptz
                ELSE public.crm_dealer_clients.last_contact_at
            END,
            next_follow_up_at = CASE
                WHEN item ? 'next_follow_up_at' THEN NULLIF(item->>'next_follow_up_at', '')::timestamptz
                ELSE public.crm_dealer_clients.next_follow_up_at
            END
        WHERE public.crm_dealer_clients.dealer_id = EXCLUDED.dealer_id
          AND public.crm_dealer_clients.updated_at < EXCLUDED.updated_at
        RETURNING * INTO result_record;

        IF NOT FOUND THEN
            SELECT * INTO result_record
            FROM public.crm_dealer_clients
            WHERE id = (item->>'id')::uuid
              AND dealer_id = v_dealer_id;
        END IF;

        results := results || to_jsonb(result_record);
    END LOOP;

    RETURN results;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sync_clients(jsonb) TO authenticated;

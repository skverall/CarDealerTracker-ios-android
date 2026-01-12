-- ============================================================================
-- Fix for Parts Sync (Missing 'code' field)
-- ============================================================================

-- The sync_parts function was missing the 'code' column which exists in the table.

CREATE OR REPLACE FUNCTION public.sync_parts(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    item jsonb;
    v_id uuid;
    v_dealer_id uuid;
    existing_updated_at timestamptz;
    incoming_updated_at timestamptz;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(payload)
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;

        -- Check existing record
        SELECT updated_at INTO existing_updated_at
        FROM crm_parts WHERE id = v_id;

        -- Last-write-wins: only update if incoming is newer or record doesn't exist
        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_parts (
                id, dealer_id, name, code, category, notes,
                created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
                v_id,
                v_dealer_id,
                item->>'name',
                item->>'code', -- Added missing code field
                item->>'category',
                item->>'notes',
                COALESCE((item->>'created_at')::timestamptz, now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                name = EXCLUDED.name,
                code = EXCLUDED.code, -- Added missing code field
                category = EXCLUDED.category,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_parts(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_vehicles(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    v_id uuid;
    v_dealer_id uuid;
    existing_updated_at timestamptz;
    incoming_updated_at timestamptz;
    normalized_vin text;
    normalized_inventory_id text;
    has_inventory_id boolean;
    existing_vin_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;
        normalized_vin := upper(trim(COALESCE(item->>'vin', '')));
        has_inventory_id := item ? 'inventory_id';
        normalized_inventory_id := NULLIF(trim(COALESCE(item->>'inventory_id', '')), '');
        PERFORM public.assert_crm_access(v_dealer_id);

        IF length(normalized_vin) = 17 THEN
            SELECT id INTO existing_vin_id
            FROM crm.vehicles
            WHERE dealer_id = v_dealer_id
              AND deleted_at IS NULL
              AND upper(trim(vin)) = normalized_vin
              AND id <> v_id
            LIMIT 1;

            IF existing_vin_id IS NOT NULL THEN
                RAISE EXCEPTION USING
                    ERRCODE = '23505',
                    MESSAGE = 'VIN_CONFLICT',
                    DETAIL = existing_vin_id::text;
            END IF;
        END IF;

        SELECT updated_at INTO existing_updated_at
        FROM crm.vehicles
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.vehicles (
                id,
                dealer_id,
                vin,
                inventory_id,
                make,
                model,
                year,
                purchase_price,
                purchase_account_id,
                purchase_date,
                status,
                notes,
                created_at,
                sale_price,
                sale_date,
                photo_url,
                asking_price,
                report_url,
                mileage,
                updated_at,
                deleted_at
            )
            VALUES (
                v_id,
                v_dealer_id,
                normalized_vin,
                normalized_inventory_id,
                item->>'make',
                item->>'model',
                (item->>'year')::int,
                (item->>'purchase_price')::decimal,
                (item->>'purchase_account_id')::uuid,
                COALESCE(public.parse_crm_calendar_date(item->>'purchase_date', NULL::date), CURRENT_DATE),
                item->>'status',
                item->>'notes',
                public.parse_crm_timestamp(item->>'created_at', now()),
                (item->>'sale_price')::decimal,
                public.parse_crm_calendar_date(item->>'sale_date', NULL::date),
                item->>'photo_url',
                (item->>'asking_price')::decimal,
                item->>'report_url',
                COALESCE((item->>'mileage')::int, 0),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                vin = EXCLUDED.vin,
                inventory_id = CASE
                    WHEN has_inventory_id THEN EXCLUDED.inventory_id
                    ELSE crm.vehicles.inventory_id
                END,
                make = EXCLUDED.make,
                model = EXCLUDED.model,
                year = EXCLUDED.year,
                purchase_price = EXCLUDED.purchase_price,
                purchase_account_id = EXCLUDED.purchase_account_id,
                purchase_date = EXCLUDED.purchase_date,
                status = EXCLUDED.status,
                notes = EXCLUDED.notes,
                sale_price = EXCLUDED.sale_price,
                sale_date = EXCLUDED.sale_date,
                photo_url = EXCLUDED.photo_url,
                asking_price = EXCLUDED.asking_price,
                report_url = EXCLUDED.report_url,
                mileage = EXCLUDED.mileage,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.vehicles.dealer_id = EXCLUDED.dealer_id
              AND crm.vehicles.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sync_vehicles(jsonb) TO authenticated;

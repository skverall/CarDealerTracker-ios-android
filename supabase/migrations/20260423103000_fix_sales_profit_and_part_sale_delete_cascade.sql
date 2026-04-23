CREATE OR REPLACE FUNCTION public.sync_sales(payload jsonb)
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
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;
        PERFORM public.assert_crm_access(v_dealer_id);

        SELECT updated_at INTO existing_updated_at
        FROM crm.sales
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.sales (
                id,
                dealer_id,
                vehicle_id,
                amount,
                sale_price,
                profit,
                date,
                buyer_name,
                buyer_phone,
                payment_method,
                account_id,
                vat_refund_percent,
                vat_refund_amount,
                notes,
                deal_desk_payload,
                deal_desk_template_code,
                deal_desk_template_version,
                jurisdiction_type,
                jurisdiction_code,
                out_the_door_total,
                cash_received_now,
                amount_financed,
                monthly_payment_estimate,
                created_at,
                updated_at,
                deleted_at
            )
            VALUES (
                v_id,
                v_dealer_id,
                (item->>'vehicle_id')::uuid,
                COALESCE((item->>'amount')::decimal, 0),
                COALESCE((item->>'sale_price')::decimal, (item->>'amount')::decimal),
                COALESCE((item->>'profit')::decimal, 0),
                COALESCE(public.parse_crm_calendar_date(item->>'date', NULL::date), CURRENT_DATE),
                item->>'buyer_name',
                item->>'buyer_phone',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                (item->>'vat_refund_percent')::decimal,
                (item->>'vat_refund_amount')::decimal,
                item->>'notes',
                CASE WHEN item ? 'deal_desk_payload' THEN item->'deal_desk_payload' ELSE NULL END,
                CASE WHEN item ? 'deal_desk_template_code' THEN NULLIF(item->>'deal_desk_template_code', '') ELSE NULL END,
                CASE WHEN item ? 'deal_desk_template_version' THEN GREATEST(COALESCE((item->>'deal_desk_template_version')::integer, 1), 1) ELSE NULL END,
                CASE WHEN item ? 'jurisdiction_type' THEN NULLIF(item->>'jurisdiction_type', '') ELSE NULL END,
                CASE WHEN item ? 'jurisdiction_code' THEN NULLIF(item->>'jurisdiction_code', '') ELSE NULL END,
                CASE WHEN item ? 'out_the_door_total' THEN (item->>'out_the_door_total')::numeric ELSE NULL END,
                CASE WHEN item ? 'cash_received_now' THEN (item->>'cash_received_now')::numeric ELSE NULL END,
                CASE WHEN item ? 'amount_financed' THEN (item->>'amount_financed')::numeric ELSE NULL END,
                CASE WHEN item ? 'monthly_payment_estimate' THEN (item->>'monthly_payment_estimate')::numeric ELSE NULL END,
                public.parse_crm_timestamp(item->>'created_at', now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                vehicle_id = EXCLUDED.vehicle_id,
                amount = EXCLUDED.amount,
                sale_price = EXCLUDED.sale_price,
                profit = CASE
                    WHEN item ? 'profit' AND item->>'profit' IS NOT NULL THEN (item->>'profit')::decimal
                    ELSE crm.sales.profit
                END,
                date = EXCLUDED.date,
                buyer_name = EXCLUDED.buyer_name,
                buyer_phone = EXCLUDED.buyer_phone,
                payment_method = EXCLUDED.payment_method,
                account_id = EXCLUDED.account_id,
                vat_refund_percent = EXCLUDED.vat_refund_percent,
                vat_refund_amount = EXCLUDED.vat_refund_amount,
                notes = EXCLUDED.notes,
                deal_desk_payload = CASE
                    WHEN item ? 'deal_desk_payload' THEN item->'deal_desk_payload'
                    ELSE crm.sales.deal_desk_payload
                END,
                deal_desk_template_code = CASE
                    WHEN item ? 'deal_desk_template_code' THEN NULLIF(item->>'deal_desk_template_code', '')
                    ELSE crm.sales.deal_desk_template_code
                END,
                deal_desk_template_version = CASE
                    WHEN item ? 'deal_desk_template_version' THEN GREATEST(COALESCE((item->>'deal_desk_template_version')::integer, 1), 1)
                    ELSE crm.sales.deal_desk_template_version
                END,
                jurisdiction_type = CASE
                    WHEN item ? 'jurisdiction_type' THEN NULLIF(item->>'jurisdiction_type', '')
                    ELSE crm.sales.jurisdiction_type
                END,
                jurisdiction_code = CASE
                    WHEN item ? 'jurisdiction_code' THEN NULLIF(item->>'jurisdiction_code', '')
                    ELSE crm.sales.jurisdiction_code
                END,
                out_the_door_total = CASE
                    WHEN item ? 'out_the_door_total' THEN (item->>'out_the_door_total')::numeric
                    ELSE crm.sales.out_the_door_total
                END,
                cash_received_now = CASE
                    WHEN item ? 'cash_received_now' THEN (item->>'cash_received_now')::numeric
                    ELSE crm.sales.cash_received_now
                END,
                amount_financed = CASE
                    WHEN item ? 'amount_financed' THEN (item->>'amount_financed')::numeric
                    ELSE crm.sales.amount_financed
                END,
                monthly_payment_estimate = CASE
                    WHEN item ? 'monthly_payment_estimate' THEN (item->>'monthly_payment_estimate')::numeric
                    ELSE crm.sales.monthly_payment_estimate
                END,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.sales.dealer_id = EXCLUDED.dealer_id
              AND crm.sales.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_part_sales(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    v_now timestamptz := now();
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm_part_sales
    SET deleted_at = v_now,
        updated_at = v_now
    WHERE id = p_id
      AND dealer_id = p_dealer_id;

    UPDATE crm_part_sale_line_items
    SET deleted_at = v_now,
        updated_at = v_now
    WHERE sale_id = p_id
      AND dealer_id = p_dealer_id
      AND deleted_at IS NULL;
END;
$function$;

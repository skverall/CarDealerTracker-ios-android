-- Migration: Add VAT refund columns to crm.sales (Base Table)
-- Date: 2026-01-12
-- Description: Adds vat_refund_percent and vat_refund_amount columns to support Korean VAT refund tracking

-- 1. Add columns to crm.sales table (Base Table)
ALTER TABLE crm.sales 
ADD COLUMN IF NOT EXISTS vat_refund_percent DECIMAL(5,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS vat_refund_amount DECIMAL(15,2) DEFAULT NULL;

-- 2. Recreate VIEW in public schema to expose the new columns
DROP VIEW IF EXISTS public.crm_sales;
CREATE OR REPLACE VIEW public.crm_sales AS
SELECT * FROM crm.sales;

-- Grant permissions on the new view
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_sales TO authenticated;

-- 3. Update sync_sales function to handle new columns (matching sync_parts pattern)
-- Must drop first because return type changed from jsonb to void
DROP FUNCTION IF EXISTS public.sync_sales(jsonb);

CREATE OR REPLACE FUNCTION public.sync_sales(payload jsonb)
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

        -- Check existing record (in base table or view)
        SELECT updated_at INTO existing_updated_at
        FROM crm.sales WHERE id = v_id;

        -- Last-write-wins logic
        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.sales (
                id,
                dealer_id,
                vehicle_id,
                amount,
                date,
                buyer_name,
                buyer_phone,
                payment_method,
                account_id,
                vat_refund_percent,
                vat_refund_amount,
                created_at,
                updated_at,
                deleted_at
            ) VALUES (
                v_id,
                v_dealer_id,
                (item->>'vehicle_id')::uuid,
                COALESCE((item->>'amount')::decimal, 0),
                COALESCE((item->>'date')::timestamptz, now()),
                item->>'buyer_name',
                item->>'buyer_phone',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                (item->>'vat_refund_percent')::decimal,
                (item->>'vat_refund_amount')::decimal,
                COALESCE((item->>'created_at')::timestamptz, now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                vehicle_id = EXCLUDED.vehicle_id,
                amount = EXCLUDED.amount,
                date = EXCLUDED.date,
                buyer_name = EXCLUDED.buyer_name,
                buyer_phone = EXCLUDED.buyer_phone,
                payment_method = EXCLUDED.payment_method,
                account_id = EXCLUDED.account_id,
                vat_refund_percent = EXCLUDED.vat_refund_percent,
                vat_refund_amount = EXCLUDED.vat_refund_amount,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at;
        END IF;
    END LOOP;
END;
$$;

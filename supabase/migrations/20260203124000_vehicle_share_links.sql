-- Migration: Vehicle share links
-- Date: 2026-02-03
-- Description: Public share links for vehicles (dealer-controlled).

-- 1) Table
CREATE TABLE IF NOT EXISTS crm.vehicle_share_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES crm.vehicles(id) ON DELETE CASCADE,
    contact_phone TEXT,
    contact_whatsapp TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_shared_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_vehicle_share_links_dealer_id ON crm.vehicle_share_links(dealer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_share_links_vehicle_id ON crm.vehicle_share_links(vehicle_id);

-- 2) RLS
ALTER TABLE crm.vehicle_share_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vehicle_share_links_select" ON crm.vehicle_share_links;
CREATE POLICY "vehicle_share_links_select" ON crm.vehicle_share_links FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_share_links_insert" ON crm.vehicle_share_links;
CREATE POLICY "vehicle_share_links_insert" ON crm.vehicle_share_links FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_share_links_update" ON crm.vehicle_share_links;
CREATE POLICY "vehicle_share_links_update" ON crm.vehicle_share_links FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_share_links_delete" ON crm.vehicle_share_links;
CREATE POLICY "vehicle_share_links_delete" ON crm.vehicle_share_links FOR DELETE
    USING (crm_can_access(dealer_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON crm.vehicle_share_links TO authenticated;

-- 3) RPC to create/update and return token
DROP FUNCTION IF EXISTS public.create_vehicle_share_link(uuid, uuid, text, text);
CREATE OR REPLACE FUNCTION public.create_vehicle_share_link(
    p_vehicle_id uuid,
    p_dealer_id uuid,
    p_contact_phone text,
    p_contact_whatsapp text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id uuid;
BEGIN
    SELECT id INTO v_id
    FROM crm.vehicle_share_links
    WHERE vehicle_id = p_vehicle_id
      AND dealer_id = p_dealer_id
      AND is_active = true
    LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO crm.vehicle_share_links (
            dealer_id,
            vehicle_id,
            contact_phone,
            contact_whatsapp,
            created_at,
            updated_at,
            last_shared_at
        ) VALUES (
            p_dealer_id,
            p_vehicle_id,
            p_contact_phone,
            p_contact_whatsapp,
            now(),
            now(),
            now()
        ) RETURNING id INTO v_id;
    ELSE
        UPDATE crm.vehicle_share_links
        SET contact_phone = p_contact_phone,
            contact_whatsapp = p_contact_whatsapp,
            updated_at = now(),
            last_shared_at = now()
        WHERE id = v_id;
    END IF;

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_vehicle_share_link(uuid, uuid, text, text) TO authenticated;

-- 4) Public view for edge function access
DROP VIEW IF EXISTS public.vehicle_share_links;
CREATE OR REPLACE VIEW public.vehicle_share_links AS
SELECT
    id,
    dealer_id,
    vehicle_id,
    contact_phone,
    contact_whatsapp,
    is_active,
    created_at,
    updated_at,
    last_shared_at
FROM crm.vehicle_share_links;

GRANT SELECT ON public.vehicle_share_links TO authenticated;

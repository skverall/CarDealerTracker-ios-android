-- Migration: Vehicle photos metadata
-- Date: 2026-02-03
-- Description: Store multiple photos per vehicle with RLS + server_updated_at.

-- 1) Table
CREATE TABLE IF NOT EXISTS crm.vehicle_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES crm.vehicles(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_modified_by UUID
);

-- 2) Indexes
CREATE INDEX IF NOT EXISTS idx_vehicle_photos_dealer_id ON crm.vehicle_photos(dealer_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_photos_vehicle_id ON crm.vehicle_photos(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_photos_server_updated_at ON crm.vehicle_photos(server_updated_at);

-- 3) Triggers
DROP TRIGGER IF EXISTS trg_vehicle_photos_server_updated_at ON crm.vehicle_photos;
CREATE TRIGGER trg_vehicle_photos_server_updated_at
    BEFORE INSERT OR UPDATE ON crm.vehicle_photos
    FOR EACH ROW EXECUTE FUNCTION public.update_server_updated_at();

-- 4) RLS policies
ALTER TABLE crm.vehicle_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vehicle_photos_select" ON crm.vehicle_photos;
CREATE POLICY "vehicle_photos_select" ON crm.vehicle_photos FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_photos_insert" ON crm.vehicle_photos;
CREATE POLICY "vehicle_photos_insert" ON crm.vehicle_photos FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_photos_update" ON crm.vehicle_photos;
CREATE POLICY "vehicle_photos_update" ON crm.vehicle_photos FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_photos_delete" ON crm.vehicle_photos;
CREATE POLICY "vehicle_photos_delete" ON crm.vehicle_photos FOR DELETE
    USING (crm_can_access(dealer_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON crm.vehicle_photos TO authenticated;

-- 5) Public view for app access (consistent with other CRM views)
DROP VIEW IF EXISTS public.crm_vehicle_photos;
CREATE OR REPLACE VIEW public.crm_vehicle_photos AS
SELECT
    id,
    dealer_id,
    vehicle_id,
    storage_path,
    sort_order,
    created_at,
    updated_at,
    deleted_at,
    server_updated_at,
    last_modified_by
FROM crm.vehicle_photos;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_vehicle_photos TO authenticated;


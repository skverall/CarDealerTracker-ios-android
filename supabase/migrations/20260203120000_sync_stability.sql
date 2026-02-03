CREATE OR REPLACE FUNCTION public.update_server_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.server_updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT conrelid::regclass AS tbl
        FROM pg_constraint
        WHERE conname = 'idx_unique_vehicles'
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS idx_unique_vehicles', r.tbl);
    END LOOP;
END $$;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'i'
          AND c.relname = 'idx_unique_vehicles'
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I.%I', r.nspname, r.relname);
    END LOOP;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'crm'
          AND table_name = 'vehicles'
          AND column_name IN ('dealer_id', 'vin')
    ) THEN
        CREATE INDEX IF NOT EXISTS idx_crm_vehicles_dealer_vin
            ON crm.vehicles (dealer_id, vin);

        -- Unique only for normalized VINs that are exactly 17 chars and not deleted
        CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_vehicles_unique_vin_17
            ON crm.vehicles (dealer_id, upper(trim(vin)))
            WHERE length(trim(vin)) = 17 AND deleted_at IS NULL;
    END IF;
END $$;

DO $$
DECLARE
    t TEXT;
    s TEXT;
    tables TEXT[] := ARRAY[
        'vehicles',
        'expenses',
        'sales',
        'dealer_clients',
        'dealer_users',
        'financial_accounts',
        'expense_templates',
        'account_transactions',
        'debts',
        'debt_payments'
    ];
    schemas TEXT[] := ARRAY['crm', 'public'];
    idx_name TEXT;
    trg_name TEXT;
BEGIN
    FOREACH t IN ARRAY tables
    LOOP
        FOREACH s IN ARRAY schemas
        LOOP
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = s
                  AND table_name = t
                  AND table_type = 'BASE TABLE'
            ) THEN
                EXECUTE format(
                    'ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()',
                    s, t
                );

                idx_name := format('idx_%s_%s_server_updated_at', s, t);
                EXECUTE format(
                    'CREATE INDEX IF NOT EXISTS %I ON %I.%I (server_updated_at)',
                    idx_name, s, t
                );

                trg_name := format('trg_%s_%s_server_updated_at', s, t);
                EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I', trg_name, s, t);
                EXECUTE format(
                    'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION public.update_server_updated_at()',
                    trg_name, s, t
                );
            END IF;
        END LOOP;
    END LOOP;
END $$;

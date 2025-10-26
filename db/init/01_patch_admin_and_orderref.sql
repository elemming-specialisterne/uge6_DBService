/* ============================================================================
 - Adds users.is_admin (BOOLEAN, default FALSE) if missing.
 - Adds orders.external_ref (TEXT) + unique index for idempotent order seeding.
 - Safe to run multiple times (checks information_schema + IF NOT EXISTS).
 ============================================================================ */
-- Add users.is_admin if it does not exist
DO $$ BEGIN IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
        AND table_name = 'users'
        AND column_name = 'is_admin'
) THEN
ALTER TABLE public.users
ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE;
END IF;
END $$;
-- Add orders.external_ref + unique index for stable upserts if missing
DO $$ BEGIN IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
        AND table_name = 'orders'
        AND column_name = 'external_ref'
) THEN
ALTER TABLE public.orders
ADD COLUMN external_ref TEXT;
-- Prevent duplicate external_refs and enable idempotent seeds
CREATE UNIQUE INDEX IF NOT EXISTS ux_orders_external_ref ON public.orders(external_ref);
END IF;
END $$;
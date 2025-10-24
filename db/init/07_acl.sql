-- 07_acl.sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='web_anon') THEN CREATE ROLE web_anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_user') THEN CREATE ROLE app_user NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='admin') THEN CREATE ROLE admin NOINHERIT; END IF;
END $$;

-- lock down schema
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO web_anon, app_user, admin;

-- products
REVOKE ALL ON TABLE public.products FROM PUBLIC;
GRANT SELECT            ON TABLE public.products TO web_anon;
GRANT SELECT, DELETE    ON TABLE public.products TO app_user;
GRANT ALL PRIVILEGES    ON TABLE public.products TO admin;

DROP POLICY IF EXISTS p_products_select ON public.products;
CREATE POLICY p_products_select ON public.products
  FOR SELECT TO web_anon, app_user, admin USING (true);

DROP POLICY IF EXISTS p_products_delete ON public.products;
CREATE POLICY p_products_delete ON public.products
  FOR DELETE TO app_user, admin USING (true);

DROP POLICY IF EXISTS p_products_write ON public.products;
CREATE POLICY p_products_write ON public.products
  FOR ALL TO admin USING (true) WITH CHECK (true);

-- orders (example: only admin full, users read; tune as needed)
REVOKE ALL ON TABLE public.orders FROM PUBLIC;
GRANT SELECT            ON TABLE public.orders TO web_anon, app_user;
GRANT ALL PRIVILEGES    ON TABLE public.orders TO admin;

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_orders_select ON public.orders;
CREATE POLICY p_orders_select ON public.orders
  FOR SELECT TO web_anon, app_user, admin USING (true);

DROP POLICY IF EXISTS p_orders_write ON public.orders;
CREATE POLICY p_orders_write ON public.orders
  FOR ALL TO admin USING (true) WITH CHECK (true);

-- product_order
REVOKE ALL ON TABLE public.product_order FROM PUBLIC;
GRANT SELECT            ON TABLE public.product_order TO web_anon, app_user;
GRANT ALL PRIVILEGES    ON TABLE public.product_order TO admin;

ALTER TABLE public.product_order ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_po_select ON public.product_order;
CREATE POLICY p_po_select ON public.product_order
  FOR SELECT TO web_anon, app_user, admin USING (true);

DROP POLICY IF EXISTS p_po_write ON public.product_order;
CREATE POLICY p_po_write ON public.product_order
  FOR ALL TO admin USING (true) WITH CHECK (true);

-- sequences (admin only)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO admin;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;

-- future objects: keep behavior consistent
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT             ON TABLES TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, DELETE     ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES     ON TABLES TO admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT      ON SEQUENCES TO admin;

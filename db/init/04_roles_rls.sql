/* ============================================================================
RLS policies:
- Admin: full access via claim role = app_admin
- User: can read/write only own orders and their lines (via claim user_id)
- Guests: products only (handled by grants)
============================================================================ */
-- roles
DO $$BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='web_anon')  THEN CREATE ROLE web_anon  NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_user')  THEN CREATE ROLE app_user  NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_admin') THEN CREATE ROLE app_admin NOLOGIN; END IF;
END$$;

-- grants
REVOKE ALL ON SCHEMA public FROM web_anon;
GRANT  USAGE ON SCHEMA public TO web_anon;
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM web_anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM web_anon;
GRANT SELECT ON public.products TO web_anon;

GRANT USAGE ON SCHEMA public TO app_user, app_admin;
GRANT SELECT ON public.products TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders, public.order_items TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO app_admin;

-- helpers
CREATE OR REPLACE FUNCTION public.jwt_user_id() RETURNS BIGINT
LANGUAGE sql STABLE AS $$
  SELECT CASE
           WHEN (NULLIF(current_setting('request.jwt.claims', true),'')::json->>'user_id') ~ '^\d+$'
           THEN (NULLIF(current_setting('request.jwt.claims', true),'')::json->>'user_id')::bigint
           ELSE NULL
         END
$$;

CREATE OR REPLACE FUNCTION public.jwt_role() RETURNS TEXT
LANGUAGE sql STABLE AS $$
  SELECT current_setting('request.jwt.claims', true)::json->>'role'
$$;

-- RLS
ALTER TABLE public.orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders      FORCE ROW LEVEL SECURITY;
ALTER TABLE public.order_items FORCE ROW LEVEL SECURITY;

-- admin policies
DROP POLICY IF EXISTS orders_admin_all ON public.orders;
CREATE POLICY orders_admin_all ON public.orders
  FOR ALL USING (jwt_role() = 'app_admin') WITH CHECK (jwt_role() = 'app_admin');

DROP POLICY IF EXISTS items_admin_all ON public.order_items;
CREATE POLICY items_admin_all ON public.order_items
  FOR ALL USING (jwt_role() = 'app_admin') WITH CHECK (jwt_role() = 'app_admin');

-- user policies — ORDERS
DROP POLICY IF EXISTS orders_user_select ON public.orders;
CREATE POLICY orders_user_select ON public.orders
  FOR SELECT TO app_user
  USING (userid = public.jwt_user_id());

DROP POLICY IF EXISTS orders_user_insert ON public.orders;
CREATE POLICY orders_user_insert ON public.orders
  FOR INSERT TO app_user
  WITH CHECK (userid = public.jwt_user_id());

DROP POLICY IF EXISTS orders_user_update ON public.orders;
CREATE POLICY orders_user_update ON public.orders
  FOR UPDATE TO app_user
  USING (userid = public.jwt_user_id())
  WITH CHECK (userid = public.jwt_user_id());

DROP POLICY IF EXISTS orders_user_delete ON public.orders;
CREATE POLICY orders_user_delete ON public.orders
  FOR DELETE TO app_user
  USING (userid = public.jwt_user_id());

-- user policies — ORDER_ITEMS (gate by parent order)
DROP POLICY IF EXISTS items_user_select ON public.order_items;
CREATE POLICY items_user_select ON public.order_items
  FOR SELECT TO app_user
  USING (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.orderid = order_items.orderid
      AND o.userid  = public.jwt_user_id()
  ));

DROP POLICY IF EXISTS items_user_insert ON public.order_items;
CREATE POLICY items_user_insert ON public.order_items
  FOR INSERT TO app_user
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.orderid = order_items.orderid
      AND o.userid  = public.jwt_user_id()
  ));

DROP POLICY IF EXISTS items_user_update ON public.order_items;
CREATE POLICY items_user_update ON public.order_items
  FOR UPDATE TO app_user
  USING (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.orderid = order_items.orderid
      AND o.userid  = public.jwt_user_id()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.orderid = order_items.orderid
      AND o.userid  = public.jwt_user_id()
  ));

DROP POLICY IF EXISTS items_user_delete ON public.order_items;
CREATE POLICY items_user_delete ON public.order_items
  FOR DELETE TO app_user
  USING (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.orderid = order_items.orderid
      AND o.userid  = public.jwt_user_id()
  ));

-- ./db/init/00_schema.sql
-- Bootstrap extensions, schemas, tables. Auth, roles, RPC live in 05–07 files.

-----------------------------
-- Extensions
-----------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pgjwt;

-----------------------------
-- Schemas
-----------------------------
CREATE SCHEMA IF NOT EXISTS auth;   -- RPC lives here (defined in 05_auth.sql)

-----------------------------
-- System settings (JWT secret for signing)
-----------------------------
DO $$
BEGIN
  PERFORM set_config('app.jwt_secret',
    'vK/5XZDYyHyggZ1GMk232JSAz42tq55mNM/0CoXIfa2hcfsKKuB1rNW8yiInSvQZ',
    true
  );
  EXECUTE $$ALTER SYSTEM SET app.jwt_secret =
    'vK/5XZDYyHyggZ1GMk232JSAz42tq55mNM/0CoXIfa2hcfsKKuB1rNW8yiInSvQZ'$$;
EXCEPTION WHEN insufficient_privilege THEN
  PERFORM 1;
END$$;

-----------------------------
-- Application tables (public)
-----------------------------

-- Business roles (referenced by users.role_name)
CREATE TABLE IF NOT EXISTS public.role (
  name  TEXT PRIMARY KEY,
  admin BOOLEAN NOT NULL DEFAULT FALSE
);

-- Users
CREATE TABLE IF NOT EXISTS public.users (
  userid         BIGSERIAL PRIMARY KEY,
  username       TEXT NOT NULL UNIQUE,
  name           TEXT,
  email          TEXT UNIQUE,
  password_hash  TEXT NOT NULL,
  role_name      TEXT NOT NULL REFERENCES public.role(name)
);

-- Products
CREATE TABLE IF NOT EXISTS public.products (
  productid   BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  description TEXT,
  price       NUMERIC(10,2) NOT NULL CHECK (price >= 0)
);

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
  orderid     BIGSERIAL PRIMARY KEY,
  userid      BIGINT NOT NULL REFERENCES public.users(userid) ON DELETE RESTRICT,
  price       NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- Order items/lines
CREATE TABLE IF NOT EXISTS public.product_order (
  orderid     BIGINT NOT NULL REFERENCES public.orders(orderid)     ON DELETE CASCADE,
  productid   BIGINT NOT NULL REFERENCES public.products(productid) ON DELETE RESTRICT,
  qty         INTEGER NOT NULL CHECK (qty > 0),
  unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
  line_total  NUMERIC(12,2) GENERATED ALWAYS AS (qty * unit_price) STORED,
  PRIMARY KEY (orderid, productid)
);


-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_userid          ON public.orders(userid);
CREATE INDEX IF NOT EXISTS idx_product_order_product  ON public.product_order(productid);
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username   ON public.users(username);
CREATE UNIQUE INDEX IF NOT EXISTS ux_products_name    ON public.products(name);

-----------------------------
-- Order total recalculation
-----------------------------
CREATE OR REPLACE FUNCTION public.recalc_order_total(p_orderid BIGINT)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.orders o
  SET price = COALESCE((
    SELECT SUM(line_total) FROM public.product_order WHERE orderid = p_orderid
  ), 0)
  WHERE o.orderid = p_orderid;
END$$;

DROP TRIGGER IF EXISTS trg_po_aiud_recalc ON public.product_order;
CREATE TRIGGER trg_po_aiud_recalc
AFTER INSERT OR UPDATE OR DELETE ON public.product_order
FOR EACH ROW
EXECUTE FUNCTION public.recalc_order_total(COALESCE(NEW.orderid, OLD.orderid));


-----------------------------
-- Base data
-----------------------------
INSERT INTO public.role (name, admin) VALUES
  ('admin', true),
  ('user',  false),
  ('guest', false)
ON CONFLICT DO NOTHING;

-- Example users (password = 1234)
INSERT INTO public.users (username, name, email, password_hash, role_name) VALUES
  ('alice','Alice','alice@example.com', crypt('1234', gen_salt('bf')), 'user'),
  ('bob','Bob','bob@example.com',       crypt('1234', gen_salt('bf')), 'admin'),
  ('gary','Gary','gary@example.com',    crypt('1234', gen_salt('bf')), 'guest')
ON CONFLICT DO NOTHING;

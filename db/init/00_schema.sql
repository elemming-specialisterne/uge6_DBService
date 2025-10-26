/* ============================================================================
 - Creates 4 tables: users, products, orders, order_items
 - Enforces FKs: orders -> users (RESTRICT), order_items -> orders (CASCADE), order_items ->products (RESTRICT)
 - Keeps timestamps: created_at, updated_at; auto-updates updated_at on UPDATE
 - Calculates orders.total from order_items via trigger on insert/update/delete
 - Idempotent: IF NOT EXISTS and DROP TRIGGER IF EXISTS used
 ============================================================================ */
-----------------------------
-- Extensions
-----------------------------
-- Needed if you plan to store password hashes using crypt()/gen_salt()
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-----------------------------
-- Tables
-----------------------------
-- Users: one row per account
CREATE TABLE IF NOT EXISTS public.users (
  userid BIGSERIAL PRIMARY KEY,
  -- surrogate key
  username TEXT NOT NULL UNIQUE,
  -- login or handle
  name TEXT,
  -- display name
  email TEXT UNIQUE,
  -- optional, unique if present
  password_hash TEXT NOT NULL,
  -- store hashed password
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Products: sellable items
CREATE TABLE IF NOT EXISTS public.products (
  productid BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  -- natural unique name
  description TEXT,
  price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Orders: header row; totals maintained by trigger from order_items
CREATE TABLE IF NOT EXISTS public.orders (
  orderid BIGSERIAL PRIMARY KEY,
  userid BIGINT NOT NULL -- who placed it
  REFERENCES public.users(userid) ON UPDATE CASCADE -- cannot remove user if orders exist
  ON DELETE RESTRICT,
  -- recomputed by trigger
  total NUMERIC(12, 2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Order lines: composite PK prevents duplicate product per order
CREATE TABLE IF NOT EXISTS public.order_items (
  orderid BIGINT NOT NULL REFERENCES public.orders(orderid) ON UPDATE CASCADE -- deleting order removes its lines
  ON DELETE CASCADE,
  productid BIGINT NOT NULL REFERENCES public.products(productid) ON UPDATE CASCADE -- block delete if product is used
  ON DELETE RESTRICT,
  qty INTEGER NOT NULL CHECK (qty > 0),
  unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
  line_total NUMERIC(12, 2) GENERATED ALWAYS AS (qty * unit_price) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (orderid, productid)
);
-----------------------------
-- Indexes
-----------------------------
-- Speed up common lookups
CREATE INDEX IF NOT EXISTS idx_orders_userid ON public.orders(userid);
CREATE INDEX IF NOT EXISTS idx_items_productid ON public.order_items(productid);
-----------------------------
-- updated_at maintenance
-----------------------------
-- Generic trigger to bump updated_at on any row UPDATE
CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now();
RETURN NEW;
END $$;
-- Make re-runs safe
DROP TRIGGER IF EXISTS trg_users_set_updated_at ON public.users;
DROP TRIGGER IF EXISTS trg_products_set_updated_at ON public.products;
DROP TRIGGER IF EXISTS trg_orders_set_updated_at ON public.orders;
DROP TRIGGER IF EXISTS trg_items_set_updated_at ON public.order_items;
-- Attach updated_at triggers
CREATE TRIGGER trg_users_set_updated_at BEFORE
UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_products_set_updated_at BEFORE
UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_orders_set_updated_at BEFORE
UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_items_set_updated_at BEFORE
UPDATE ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
-----------------------------
-- Order total recalculation
-----------------------------
-- AFTER trigger: recompute orders.total whenever order_items changes
-- Reads NEW/OLD internally; no trigger arguments needed
CREATE OR REPLACE FUNCTION public.recalc_order_total() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_orderid BIGINT;
BEGIN v_orderid := COALESCE(NEW.orderid, OLD.orderid);
UPDATE public.orders o
SET total = COALESCE(
    (
      SELECT SUM(line_total)
      FROM public.order_items
      WHERE orderid = v_orderid
    ),
    0
  ),
  updated_at = now()
WHERE o.orderid = v_orderid;
-- AFTER triggers must return NULL
RETURN NULL;
END $$;
-- Safe drop then create the recalculation trigger
DROP TRIGGER IF EXISTS trg_items_recalc_total ON public.order_items;
CREATE TRIGGER trg_items_recalc_total
AFTER
INSERT
  OR
UPDATE
  OR DELETE ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.recalc_order_total();
-- ./db/init/02_seed.sql  (CSV-based orders + lines)
BEGIN;
SET LOCAL client_min_messages = WARNING;

-- Only reset orders
TRUNCATE TABLE public.product_order, public.orders RESTART IDENTITY CASCADE;

-- === ORDERS ===
-- CSV path: /docker-entrypoint-initdb.d/05_seed_orders.csv
-- Columns: orderid,userid,created_at
CREATE TEMP TABLE st_orders(
  orderid    bigint,
  userid     bigint,
  created_at timestamptz
) ON COMMIT DROP;

COPY st_orders(orderid,userid,created_at)
FROM '/docker-entrypoint-initdb.d/05_seed_orders.csv'
WITH (FORMAT csv, HEADER true, NULL '');

-- Insert orders only if user exists. Keep explicit orderid if provided.
INSERT INTO public.orders(orderid, userid, created_at)
SELECT o.orderid, o.userid, COALESCE(o.created_at, now())
FROM st_orders o
JOIN public.users u ON u.userid = o.userid
ON CONFLICT (orderid) DO NOTHING;

-- === ORDER LINES ===
-- CSV path: /docker-entrypoint-initdb.d/06_seed_order_lines.csv
-- Columns: orderid,productid,qty,unit_price
CREATE TEMP TABLE st_lines(
  orderid    bigint,
  productid  bigint,
  qty        integer,
  unit_price numeric(10,2)
) ON COMMIT DROP;

COPY st_lines(orderid,productid,qty,unit_price)
FROM '/docker-entrypoint-initdb.d/06_seed_order_lines.csv'
WITH (FORMAT csv, HEADER true, NULL '');

-- Only insert lines where both order and product exist
INSERT INTO public.product_order(orderid,productid,qty,unit_price)
SELECT l.orderid, l.productid, l.qty, l.unit_price
FROM st_lines l
JOIN public.orders   o ON o.orderid   = l.orderid
JOIN public.products p ON p.productid = l.productid
ON CONFLICT (orderid, productid) DO NOTHING;

-- Recompute totals for all touched orders
DO $$
BEGIN
  UPDATE public.orders o
  SET price = COALESCE(s.sum_total, 0)
  FROM (
    SELECT orderid, SUM(qty * unit_price)::numeric(12,2) AS sum_total
    FROM public.product_order
    GROUP BY orderid
  ) s
  WHERE o.orderid = s.orderid;
END$$;

COMMIT;

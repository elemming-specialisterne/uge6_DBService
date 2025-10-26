/* ============================================================================
 - Loads CSVs into TEMP staging tables.
 - Upserts into users/products/orders/order_items.
 - Passwords hashed via pgcrypto (crypt + gen_salt('bf')).
 - Idempotent: ON CONFLICT for natural keys (username, name, external_ref, PKs).
 - Safe to re-run any time.
 Test:
 docker compose exec db psql -U app -d appdb -c "TABLE users; TABLE products; TABLE orders; TABLE order_items;"
 ============================================================================ */
-- 1) Staging tables (TEMP => session-scoped; always recreated)
DROP TABLE IF EXISTS stg_users;
CREATE TEMP TABLE stg_users (
    -- natural key
    username TEXT PRIMARY KEY,
    name TEXT,
    email TEXT,
    -- plaintext only in CSV, hashed on insert
    password_plain TEXT,
    is_admin BOOLEAN
);
DROP TABLE IF EXISTS stg_products;
CREATE TEMP TABLE stg_products (
    -- natural key
    name TEXT PRIMARY KEY,
    description TEXT,
    price NUMERIC(10, 2)
);
DROP TABLE IF EXISTS stg_orders;
CREATE TEMP TABLE stg_orders (
    -- natural key for idempotent orders
    external_ref TEXT PRIMARY KEY,
    -- owner (references users.username)
    username TEXT
);
DROP TABLE IF EXISTS stg_order_items;
CREATE TEMP TABLE stg_order_items (
    -- links to stg_orders.external_ref
    external_ref TEXT,
    -- links to products.name                 
    product_name TEXT,
    qty INTEGER,
    unit_price NUMERIC(10, 2)
);
-- 2) COPY CSVs from the container filesystem (mounted under /docker-entrypoint-initdb.d)
COPY stg_users
FROM '/docker-entrypoint-initdb.d/seed/users.csv' WITH (FORMAT csv, HEADER true);
COPY stg_products
FROM '/docker-entrypoint-initdb.d/seed/products.csv' WITH (FORMAT csv, HEADER true);
COPY stg_orders
FROM '/docker-entrypoint-initdb.d/seed/orders.csv' WITH (FORMAT csv, HEADER true);
COPY stg_order_items
FROM '/docker-entrypoint-initdb.d/seed/order_items.csv' WITH (FORMAT csv, HEADER true);
-- 3) Upsert users by (username)
INSERT INTO public.users (username, name, email, password_hash, is_admin)
SELECT s.username,
    s.name,
    s.email,
    -- hash plaintext
    crypt(s.password_plain, gen_salt('bf')),
    COALESCE(s.is_admin, false)
FROM stg_users s ON CONFLICT (username) DO
UPDATE
SET name = EXCLUDED.name,
    email = EXCLUDED.email,
    -- replace hash on seed re-run
    password_hash = EXCLUDED.password_hash,
    is_admin = EXCLUDED.is_admin,
    updated_at = now();
-- 4) Upsert products by (name)
INSERT INTO public.products (name, description, price)
SELECT name,
    description,
    price
FROM stg_products ON CONFLICT (name) DO
UPDATE
SET description = EXCLUDED.description,
    price = EXCLUDED.price,
    updated_at = now();
-- 5) Upsert orders by (external_ref)
INSERT INTO public.orders (external_ref, userid)
SELECT so.external_ref,
    u.userid
FROM stg_orders so
    JOIN public.users u ON u.username = so.username ON CONFLICT (external_ref) DO
UPDATE -- allow reassignment
SET userid = EXCLUDED.userid,
    updated_at = now();
-- 6) Upsert order_items by composite key (orderid, productid)
INSERT INTO public.order_items (orderid, productid, qty, unit_price)
SELECT o.orderid,
    p.productid,
    i.qty,
    i.unit_price
FROM stg_order_items i
    JOIN public.orders o ON o.external_ref = i.external_ref
    JOIN public.products p ON p.name = i.product_name ON CONFLICT (orderid, productid) DO
UPDATE
SET qty = EXCLUDED.qty,
    unit_price = EXCLUDED.unit_price,
    updated_at = now();
-- Note: orders.total is recomputed by the trigger defined in 00_schema.sql
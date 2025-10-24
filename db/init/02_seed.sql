-- 02_seed.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

BEGIN;
SET LOCAL client_min_messages = WARNING;

-- names must match 00_schema.sql
TRUNCATE TABLE
  product_order,
  orders,
  products,
  users,
  role
RESTART IDENTITY CASCADE;

-- roles (safe if also seeded elsewhere)
INSERT INTO role(name, admin) VALUES
  ('User', false), ('Admin', true)
ON CONFLICT (name) DO NOTHING;

-- users: stage -> hash -> insert
CREATE TEMP TABLE users_stage(
  username text,
  name text,
  email text,
  password_plain text,
  role_name text
) ON COMMIT DROP;

COPY users_stage(username,name,email,password_plain,role_name)
FROM '/docker-entrypoint-initdb.d/03_seed_users.csv'
WITH (FORMAT csv, HEADER true, NULL '');

INSERT INTO users(username,name,email,password_hash,role_name)
SELECT
  trim(s.username),
  NULLIF(trim(s.name),''),
  NULLIF(trim(s.email),''),
  crypt(s.password_plain, gen_salt('bf',12)),
  s.role_name
FROM users_stage s
WHERE trim(coalesce(s.username,'')) <> ''
  AND trim(coalesce(s.password_plain,'')) <> '';

-- unique indexes (new table names)
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username ON users(username);
CREATE UNIQUE INDEX IF NOT EXISTS ux_products_name ON products(name);

-- products
CREATE TEMP TABLE st_product_raw(name text, description text, price text) ON COMMIT DROP;

COPY st_product_raw(name,description,price)
FROM '/docker-entrypoint-initdb.d/04_seed_products.csv'
WITH (FORMAT csv, HEADER true, NULL '');

WITH cleaned AS (
  SELECT row_number() OVER () AS line_no,
         trim(name) AS name,
         NULLIF(trim(description),'') AS description,
         CASE WHEN trim(price) ~ '^[0-9]+(\.[0-9]{1,2})?$'
              THEN trim(price)::numeric(10,2) ELSE NULL END AS price
  FROM st_product_raw
  WHERE trim(coalesce(name,'')) <> ''
),
dedup AS (
  SELECT name, description, price
  FROM (
    SELECT name, description, price,
           row_number() OVER (PARTITION BY lower(name) ORDER BY line_no DESC) AS rn
    FROM cleaned
  ) x
  WHERE rn = 1
)
INSERT INTO products(name,description,price)
SELECT name, description, price
FROM dedup
WHERE price IS NOT NULL;

COMMIT;

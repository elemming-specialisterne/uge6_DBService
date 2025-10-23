BEGIN;
SET LOCAL client_min_messages = WARNING;

-- wipe data and reset IDs
TRUNCATE TABLE
  productorder,
  "order",
  product,
  "user"
RESTART IDENTITY CASCADE;

-- ensure uniques for CRUD
CREATE UNIQUE INDEX IF NOT EXISTS ux_user_username ON "user"(username);
CREATE UNIQUE INDEX IF NOT EXISTS ux_product_name  ON product(name);

-- ===== users (simple) =====
COPY "user"(username,name,email,role_name)
FROM '/docker-entrypoint-initdb.d/03_seed_users.csv'
WITH (FORMAT csv, HEADER true, NULL '');

-- ===== products (dedupe + safe cast) =====
CREATE TEMP TABLE st_product_raw(
  name text,
  description text,
  price text
) ON COMMIT DROP;

COPY st_product_raw(name,description,price)
FROM '/docker-entrypoint-initdb.d/04_seed_products.csv'
WITH (FORMAT csv, HEADER true, NULL '');

WITH cleaned AS (
  SELECT
    row_number() OVER ()                          AS line_no,
    trim(name)                                    AS name,
    nullif(trim(description), '')                 AS description,
    CASE
      WHEN trim(price) ~ '^[0-9]+(\.[0-9]{1,2})?$' THEN trim(price)::numeric(10,2)
      ELSE NULL
    END                                           AS price
  FROM st_product_raw
  WHERE trim(name) <> ''
),
dedup AS (
  SELECT name, description, price
  FROM (
    SELECT
      name, description, price,
      row_number() OVER (PARTITION BY lower(name) ORDER BY line_no DESC) AS rn
    FROM cleaned
  ) x
  WHERE rn = 1   -- keep last occurrence
)
INSERT INTO product(name,description,price)
SELECT name,description,price FROM dedup;

COMMIT;

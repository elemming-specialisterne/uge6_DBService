BEGIN;

-- ensure unique keys exist (safe if rerun)
CREATE UNIQUE INDEX IF NOT EXISTS ux_user_username ON "user"(username);
CREATE UNIQUE INDEX IF NOT EXISTS ux_product_name  ON product(name);

-- ===== users =====
CREATE TEMP TABLE st_user(
  username  text PRIMARY KEY,
  name      text,
  email     text,
  role_name text
) ON COMMIT DROP;

COPY st_user(username,name,email,role_name)
FROM '/docker-entrypoint-initdb.d/03_seed_users.csv'
WITH (FORMAT csv, HEADER true, NULL '');

UPDATE st_user
SET username = trim(username),
    name     = nullif(trim(name), ''),
    email    = nullif(trim(email), ''),
    role_name= nullif(trim(role_name), '');

INSERT INTO "user"(username,name,email,role_name)
SELECT username,name,email,role_name FROM st_user
ON CONFLICT (username) DO UPDATE
SET name = EXCLUDED.name,
    email = EXCLUDED.email,
    role_name = EXCLUDED.role_name;

-- ===== products =====
CREATE TEMP TABLE st_product(
  name        text PRIMARY KEY,
  description text,
  price       numeric(10,2)
) ON COMMIT DROP;

COPY st_product(name,description,price)
FROM '/docker-entrypoint-initdb.d/04_seed_products.csv'
WITH (FORMAT csv, HEADER true, NULL '');

UPDATE st_product
SET name = trim(name),
    description = nullif(trim(description), '');

INSERT INTO product(name,description,price)
SELECT name,description,price FROM st_product
ON CONFLICT (name) DO UPDATE
SET description = EXCLUDED.description,
    price = EXCLUDED.price;

COMMIT;

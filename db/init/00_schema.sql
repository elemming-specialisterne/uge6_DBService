-- ./db/init/00_schema.sql
-- Bootstrap extensions, schemas, tables, seed data.
-- Auth, roles, and grants are handled in 05_auth.sql, 06_public_login_wrapper.sql, and 07_acl.sql.

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
CREATE TABLE IF NOT EXISTS role (
  name  TEXT PRIMARY KEY,
  admin BOOLEAN NOT NULL DEFAULT FALSE
);

-- Users
CREATE TABLE IF NOT EXISTS users (
  userid         BIGSERIAL PRIMARY KEY,
  username       TEXT NOT NULL UNIQUE,
  name           TEXT,
  email          TEXT UNIQUE,
  password_hash  TEXT NOT NULL,
  role_name      TEXT NOT NULL REFERENCES role(name)
);

-- Products
CREATE TABLE IF NOT EXISTS products (
  productid   BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  description TEXT,
  price       NUMERIC(10,2) NOT NULL CHECK (price >= 0)
);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  orderid BIGSERIAL PRIMARY KEY,
  userid  BIGINT NOT NULL REFERENCES users(userid),
  price   NUMERIC(12,2) NOT NULL DEFAULT 0
);

-- Order items
CREATE TABLE IF NOT EXISTS product_order (
  orderid   BIGINT NOT NULL REFERENCES orders(orderid) ON DELETE CASCADE,
  productid BIGINT NOT NULL REFERENCES products(productid),
  qty       INTEGER NOT NULL CHECK (qty > 0),
  price     NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  PRIMARY KEY (orderid, productid)
);

-----------------------------
-- Base data
-----------------------------
INSERT INTO role (name, admin) VALUES
  ('admin', true),
  ('user',  false),
  ('guest', false)
ON CONFLICT DO NOTHING;

-- Example users (password = 1234)
INSERT INTO users (username, name, email, password_hash, role_name) VALUES
  ('alice','Alice','alice@example.com', crypt('1234', gen_salt('bf')), 'user'),
  ('bob','Bob','bob@example.com',       crypt('1234', gen_salt('bf')), 'admin'),
  ('gary','Gary','gary@example.com',    crypt('1234', gen_salt('bf')), 'guest')
ON CONFLICT DO NOTHING;
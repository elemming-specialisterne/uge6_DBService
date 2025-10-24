-- 1) Needed for crypt() / gen_salt()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2) Roles
CREATE TABLE IF NOT EXISTS role (
  name TEXT PRIMARY KEY,
  admin BOOLEAN NOT NULL DEFAULT FALSE
);

-- 3) Users  (avoid reserved word "user")
CREATE TABLE IF NOT EXISTS users (
  userid BIGSERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  name TEXT,
  email TEXT UNIQUE,
  password_hash TEXT NOT NULL,
  role_name TEXT NOT NULL REFERENCES role(name)
);

-- 4) Products
CREATE TABLE IF NOT EXISTS products (
  productid BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  price NUMERIC(10,2) NOT NULL CHECK (price >= 0)
);

-- 5) Orders
CREATE TABLE IF NOT EXISTS orders (
  orderid BIGSERIAL PRIMARY KEY,
  userid BIGINT NOT NULL REFERENCES users(userid),
  price NUMERIC(12,2) NOT NULL DEFAULT 0
);

-- 6) Order items
CREATE TABLE IF NOT EXISTS product_order (
  orderid BIGINT NOT NULL REFERENCES orders(orderid) ON DELETE CASCADE,
  productid BIGINT NOT NULL REFERENCES products(productid),
  amount INT NOT NULL CHECK (amount > 0),
  PRIMARY KEY (orderid, productid)
);
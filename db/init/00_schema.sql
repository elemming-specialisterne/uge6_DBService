CREATE TABLE role (
  name text PRIMARY KEY,
  admin boolean NOT NULL DEFAULT false
);

CREATE TABLE "user" (
  userid bigserial PRIMARY KEY,
  username text NOT NULL UNIQUE,
  name text,
  email text UNIQUE,
  role_name text NOT NULL REFERENCES role(name)
);

CREATE TABLE product (
  productid bigserial PRIMARY KEY,
  name text NOT NULL UNIQUE,
  description text,
  price numeric(10,2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE "order" (
  orderid bigserial PRIMARY KEY,
  userid bigint NOT NULL REFERENCES "user"(userid),
  price numeric(12,2) NOT NULL DEFAULT 0
);

CREATE TABLE productorder (
  orderid bigint NOT NULL REFERENCES "order"(orderid) ON DELETE CASCADE,
  productid bigint NOT NULL REFERENCES product(productid),
  amount int NOT NULL CHECK (amount > 0),
  PRIMARY KEY (orderid, productid)
);

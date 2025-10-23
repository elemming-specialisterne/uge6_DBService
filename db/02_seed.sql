\set ON_ERROR_STOP on
BEGIN;
\copy "user"(username,name,email,role_name) FROM '/docker-entrypoint-initdb.d/03_seed_users.csv' WITH (FORMAT csv, HEADER true, NULL '');
\copy product(name,description,price) FROM '/docker-entrypoint-initdb.d/04_seed_products.csv' WITH (FORMAT csv, HEADER true, NULL '');
COMMIT;

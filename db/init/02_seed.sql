BEGIN;

COPY "user"(username,name,email,role_name)
FROM '/docker-entrypoint-initdb.d/03_seed_users.csv'
WITH (FORMAT csv, HEADER true, NULL '');

COPY product(name,description,price)
FROM '/docker-entrypoint-initdb.d/04_seed_products.csv'
WITH (FORMAT csv, HEADER true, NULL '');

COMMIT;

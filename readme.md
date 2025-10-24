# uge6_DBService

Postgres + PostgREST stack with auto schema + seed on first boot.

## Stack
- Postgres 16
- PostgREST
- Docker Compose

## Prereqs
- Docker Desktop
- Git

## Project layout
```text
db/
  docker-compose.yml
  init/
    00_schema.sql
    01_seed_roles.sql
    02_seed.sql
    03_seed_users.csv
    04_seed_products.csv
    099_grants.sql
```

## Quick start
```bash
cd db
docker compose up -d
```

### Wait until Postgres is ready
```bash
docker compose logs --tail=100 db
# look for: "database system is ready to accept connections"
```

## Verify

### SQL
```bash
docker exec -it db-db-1 psql -U app -d shop -c "TABLE role;"
```
```bash
docker exec -it db-db-1 psql -U app -d shop -c "SELECT COUNT(*) FROM product;"
```


### HTTP (PostgREST)
- GET `http://localhost:3000/product?limit=5` with header `Accept: application/json`

## How it works
- Files in `init/` run **once** on first boot (when the DB volume is empty).
- `099_grants.sql` creates `web_anon` and grants read-only on `public`.

## Common tasks

### Restart without losing data
```bash
docker compose down
docker compose up -d
```

### Full reset (rerun all init scripts)
```bash
docker compose down
docker volume rm db_dbdata     # find the exact name via: docker volume ls
docker compose up -d
```

### Reseed users + products (no wipe beyond what 02_seed.sql does)
PowerShell:
```powershell
# reseed users + products (wipes and loads per 02_seed.sql)
docker exec -i db-db-1 psql -U app -d shop -v ON_ERROR_STOP=1 `
  -f /docker-entrypoint-initdb.d/02_seed.sql

# quick sanity
docker exec -it db-db-1 psql -U app -d shop -c 'SELECT count(*) AS users FROM "user";'
docker exec -it db-db-1 psql -U app -d shop -c 'SELECT count(*) AS products FROM product;'
```

Bash:
```bash
docker exec -i db-db-1 psql -U app -d shop -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/02_seed.sql
docker exec -it db-db-1 psql -U app -d shop -c 'SELECT count(*) AS users FROM "user";'
docker exec -it db-db-1 psql -U app -d shop -c 'SELECT count(*) AS products FROM product;'
```

### List tables and privileges
```bash
docker exec -it db-db-1 psql -U app -d shop -c "\dt public.*"
docker exec -it db-db-1 psql -U app -d shop -c "\dp public.*"
```

## Postman quick recipes
- Read rows: `GET /product?limit=5` with `Accept: application/json`
- `http://localhost:3000/product`
- Select columns: `GET /product?select=productid,name,price&limit=5`
- `http://localhost:3000/product?limit=5`
- Sort: append `&order=productid.desc`
- Filter: append `&price=gt.100`

## Troubleshooting
- 404 on table: wrong name or cache stale → `docker compose restart postgrest`.
- 401: `web_anon` missing → rerun `099_grants.sql`.
- 503/connection refused: DB not ready → check `docker compose logs db`.
- Seed failed: fix CSV headers, then run `02_seed.sql` or do a full reset.

## Notes
- Data is stored in a Docker **named volume** (e.g., `db_dbdata`), not in a local `pgdata` folder.
- Keep CSV headers aligned with column lists in `02_seed.sql`.
- For public exposure, prefer granting `web_anon` only on views.

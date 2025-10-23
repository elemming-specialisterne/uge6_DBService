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
~~~text
db/
  docker-compose.yml
  init/
    00_schema.sql
    01_seed_roles.sql
    02_seed.sql
    03_seed_users.csv
    04_seed_products.csv
    099_grants.sql
pgdata/           # persisted database files (gitignored)
~~~

## Quick start
~~~bash
cd db
# fresh boot (wipes DB to trigger init)
docker compose down
# PowerShell alternative:
#  Remove-Item -Recurse -Force ..\pgdata
rm -rf ../pgdata
docker compose up -d
~~~

### Wait until Postgres is ready
~~~bash
docker compose logs --tail=100 db
# look for: "database system is ready to accept connections"
~~~

## Verify

### SQL
~~~bash
docker exec -it db-db-1 psql -U app -d shop -c "TABLE role;"
docker exec -it db-db-1 psql -U app -d shop -c "SELECT COUNT(*) FROM product;"
~~~

### HTTP (PostgREST)
- Data: GET http://localhost:3000/product?limit=5 with header `Accept: application/json`

## How it works
- `init/*.sql` and CSV run **once** on first boot (when `pgdata/` is empty).
- `099_grants.sql` creates `web_anon` and grants read-only on `public` for anonymous GET.

## Common tasks

### Restart without losing data
~~~bash
docker compose down
docker compose up -d
~~~

### Re-seed from scratch
~~~bash
docker compose down
rm -rf ../pgdata
docker compose up -d
~~~

### Run seed again without wiping
~~~bash
docker exec -i db-db-1 psql -U app -d shop -f /docker-entrypoint-initdb.d/02_seed.sql
~~~

### List tables and privileges
~~~bash
docker exec -it db-db-1 psql -U app -d shop -c "\dt public.*"
docker exec -it db-db-1 psql -U app -d shop -c "\dp public.*"
~~~

## Postman quick recipes
- Read rows: GET http://localhost:3000/product?limit=5 with `Accept: application/json`
- Select columns: GET http://localhost:3000/product?select=productid,name,price&limit=5
- Sort: add `&order=productid.desc`
- Filter: add `&price=gt.100`

## Troubleshooting
- **404** on table: wrong name or cache stale → `docker compose restart postgrest`.
- **401**: `web_anon` missing → re-run `099_grants.sql`.
- **503/connection refused**: DB not ready → check `docker compose logs db`.
- **Seed failed**: use server-side `COPY` in `init/02_seed.sql` with paths `/docker-entrypoint-initdb.d/...`, then wipe `pgdata/` and `up -d` again.

## Notes
- `pgdata/` holds the database files. Do not commit. Delete to reset.
- Keep CSV headers aligned with column lists in `02_seed.sql`.
- For public exposure, prefer granting `web_anon` only on views.
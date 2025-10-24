# 🧠 uge6_DBService

Postgres + PostgREST stack with JWT auth and **RBAC (Role-Based Access Control)**.

## Stack

- PostgreSQL 16
- PostgREST 13
- Docker Compose

## Roles and Access (RBAC)

| Role                 | Description             | Access                                  |
| -------------------- | ----------------------- | --------------------------------------- |
| **guest (web_anon)** | Unauthenticated         | Read-only on public tables              |
| **user (app_user)**  | Logged-in regular user  | CRUD on `products`, read-only elsewhere |
| **admin**            | Logged-in administrator | Full CRUD on all tables and sequences   |

Authentication is handled by `auth.login`, returning a JWT with 1-hour expiry.  
Authorization (RBAC) is enforced by SQL grants and row-level security (RLS) rules in `07_acl.sql`.

---

## 📁 Project layout

```text
db/
  docker-compose.yml
  init/
    00_schema.sql
    01_seed_roles.sql
    02_seed.sql
    03_seed_users.csv
    04_seed_products.csv
    05_auth.sql
    06_public_login_wrapper.sql
    07_acl.sql
```

---

## ⚙️ Quick start

```bash
cd db
docker compose up -d
```

Wait until:

```
database system is ready to accept connections
```

Then visit:

```
http://localhost:3000/products?limit=5
```

---

## 🧪 Verify

### Guest (no token)

```bash
curl http://localhost:3000/products?limit=1       # 200
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"Nope","price":1}' http://localhost:3000/products  # 401
```

### User (RBAC → app_user)

```bash
TOKEN=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"p_username":"alice","p_password":"1234"}' \
  http://localhost:3000/rpc/login | sed -E 's/.*"token":"([^"]+)".*/\1/')

# Allowed (RBAC rule grants CRUD on products)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/products?limit=1

# Blocked (RBAC denies modifying orders)
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"userid":1,"price":100}' http://localhost:3000/orders
```

### Admin (RBAC → admin)

```bash
ADM=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"p_username":"bob","p_password":"1234"}' \
  http://localhost:3000/rpc/login | sed -E 's/.*"token":"([^"]+)".*/\1/')

# Allowed: full CRUD
curl -H "Authorization: Bearer $ADM" http://localhost:3000/orders
curl -X POST -H "Authorization: Bearer $ADM" -H "Content-Type: application/json" \
  -d '{"userid":1,"price":99.99}' http://localhost:3000/orders
```

---

## 🔁 Reset / reseed

### Soft reseed

```bash
docker exec -i db-db-1 psql -U app -d shop_db -v ON_ERROR_STOP=1 \
  -f /docker-entrypoint-initdb.d/02_seed.sql
```

### Full reset

```bash
docker compose down -v
docker compose up -d
```

---

## 🧰 Common diagnostics

| Symptom                   | Fix                                |
| ------------------------- | ---------------------------------- |
| `PGRST002 schema cache`   | Schema missing → run `05_auth.sql` |
| `401 Unauthorized`        | Missing/invalid JWT                |
| `42501 permission denied` | Check RBAC rules in `07_acl.sql`   |
| `503 Service Unavailable` | DB not ready                       |
| Need new anon role        | Re-run `07_acl.sql`                |

---

## 🧩 How RBAC works

- `auth.login` issues JWTs embedding `role` claim (`app_user`, `admin`).
- PostgREST uses the claim to **switch SQL role** at runtime.
- `07_acl.sql` defines which role can read/write each table.
- Guests (`web_anon`) default to read-only.
- Users (`app_user`) can CRUD products only.
- Admins have global privileges including orders, users, and products.

---

## ✅ Tested end-to-end (RBAC)

✔ Guest: read only  
✔ User: CRUD on products only  
✔ Admin: full access  
✔ JWT auth + RLS + RBAC all verified via `/rpc/login`

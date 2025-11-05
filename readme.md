# uge6_DBService

PostgreSQL + PostgREST stack with **JWT auth**, **RBAC**, and **Row-Level Security (RLS)**.

---

## Stack

- PostgreSQL 16  
- PostgREST (latest)  
- Docker Compose  

---

## Roles & Access

| Role (SQL)             | How you get it                 | Permissions (summary)                                                          |
|------------------------|--------------------------------|--------------------------------------------------------------------------------|
| **guest** (`web_anon`) | No token                       | Read-only on `products`                                                        |
| **user** (`app_user`)  | JWT from `/rpc/login`          | CRUD on `orders`/`order_items` **only for own `user_id`**; read `products`     |
| **admin** (`app_admin`)| JWT from `/rpc/login` (admin)  | Full CRUD everywhere                                                           |

- `/rpc/login` returns a JWT with claims: `role`, `user_id`, `iat`, `exp`.  
- PostgREST reads the `role` claim to set the SQL role per request.  
- RLS policies restrict `orders` and `order_items` to the current `user_id`.

**JWT secret** must match in two places:
- Compose → `PGRST_JWT_SECRET`  
- DB GUC → `app.jwt_secret` set by `init/05_login_rpc.sql`

---

## Project Structure

```
db/
  docker-compose.yml
  .env                     # optional (compose works without it)
  init/
    seed/
      users.csv
      products.csv
      orders.csv
      order_items.csv
    00_schema.sql
    01_patch_admin_and_orderref.sql
    02_seed_from_csv.sql
    03_postgrest_perms.sql
    04_roles_rls.sql
    05_login_rpc.sql
  scripts/
    smoke.ps1              # quick end-to-end RBAC checks
```

> The included **`scripts/smoke.ps1`** runs a quick regression of all RBAC and RLS rules using PowerShell.

---

## Quick Start

```bash
cd db
docker compose up -d
# wait until the DB healthcheck is healthy
```

API base URL: `http://localhost:3000`

Try:
```
http://localhost:3000/products?limit=5
```

Default accounts:
- User → `alice` / `1234`
- Admin → `admin` / `1234`

---

## Connect

**API base URL:** `http://localhost:3000`  
**Health check:** `GET /products?limit=1` (works without a token)

### Login & call (PowerShell)

> Note: PowerShell’s `curl` is an alias for `Invoke-WebRequest`. Use **`Invoke-RestMethod`** (shown below) or call **`curl.exe`** explicitly (see Git Bash section for real curl flags).

```powershell
$Base = "http://localhost:3000"

# user login → get JWT
$resp = Invoke-RestMethod -Method Post "$Base/rpc/login" `
  -ContentType 'application/json' `
  -Body (@{identifier='alice'; pass='1234'} | ConvertTo-Json)
$USER_TOKEN = ($resp.token) -replace "\\n","" -replace "`r","" -replace "`n",""

# call a protected endpoint
Invoke-RestMethod "$Base/orders" -Headers @{ Authorization = "Bearer $USER_TOKEN" }
```

### Login & call (Git Bash / WSL / Linux / macOS)

```bash
# user login → get JWT (requires jq)
USER_TOKEN=$(curl -s -X POST http://localhost:3000/rpc/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"alice","pass":"1234"}' | jq -r .token)

# call a protected endpoint
curl -H "Authorization: Bearer $USER_TOKEN" http://localhost:3000/orders
```

---

## Verify (Guest vs User vs Admin)

### Guest (no token)

**PowerShell**
```powershell
$Base = "http://localhost:3000"

# OK
Invoke-RestMethod "$Base/products?limit=1"

# Blocked
try {
  Invoke-RestMethod "$Base/orders"
} catch { $_.ErrorDetails.Message }
```

**Git Bash**
```bash
curl "http://localhost:3000/products?limit=1"          # 200
curl -i "http://localhost:3000/orders"                  # 401
```

### User (`alice` / `1234`)

**PowerShell**
```powershell
$Base = "http://localhost:3000"

# login → token
$u = Invoke-RestMethod -Method Post "$Base/rpc/login" `
  -ContentType 'application/json' `
  -Body (@{identifier='alice'; pass='1234'} | ConvertTo-Json)
$USER_TOKEN = ($u.token) -replace "\\n","" -replace "`r","" -replace "`n",""

# can read products
Invoke-RestMethod "$Base/products?limit=1" -Headers @{ Authorization = "Bearer $USER_TOKEN" }

# sees only own orders
Invoke-RestMethod "$Base/orders" -Headers @{ Authorization = "Bearer $USER_TOKEN" }

# cannot create order for someone else (RLS ⇒ 403)
try {
  Invoke-RestMethod -Method Post "$Base/orders" `
    -Headers @{ Authorization = "Bearer $USER_TOKEN"; 'Content-Type'='application/json' } `
    -Body (@{userid=1} | ConvertTo-Json)
} catch { $_.ErrorDetails.Message }
```

**Git Bash**
```bash
USER_TOKEN=$(curl -s -X POST http://localhost:3000/rpc/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"alice","pass":"1234"}' | jq -r .token)

# can read products
curl -H "Authorization: Bearer $USER_TOKEN" "http://localhost:3000/products?limit=1"

# sees only own orders
curl -H "Authorization: Bearer $USER_TOKEN" "http://localhost:3000/orders"

# cannot create order for someone else (RLS ⇒ 403)
curl -i -X POST "http://localhost:3000/orders" \
  -H "Authorization: Bearer $USER_TOKEN" -H "Content-Type: application/json" \
  -d '{"userid":1}'
```

### Admin (`admin` / `1234`)

**PowerShell**
```powershell
$Base = "http://localhost:3000"

# login → token
$a = Invoke-RestMethod -Method Post "$Base/rpc/login" `
  -ContentType 'application/json' `
  -Body (@{identifier='admin'; pass='1234'} | ConvertTo-Json)
$ADMIN_TOKEN = ($a.token) -replace "\\n","" -replace "`r","" -replace "`n",""

# sees all orders
Invoke-RestMethod "$Base/orders" -Headers @{ Authorization = "Bearer $ADMIN_TOKEN" }

# can update products
$headers = @{ Authorization = "Bearer $ADMIN_TOKEN"; 'Content-Type' = 'application/json' }
$body    = @{ price = 21.00 } | ConvertTo-Json
Invoke-RestMethod -Method Patch "$Base/products?name=eq.Widget" -Headers $headers -Body $body
```

**Git Bash**
```bash
ADMIN_TOKEN=$(curl -s -X POST http://localhost:3000/rpc/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"admin","pass":"1234"}' | jq -r .token)

# sees all orders
curl -H "Authorization: Bearer $ADMIN_TOKEN" "http://localhost:3000/orders"

# can update products
curl -i -X PATCH "http://localhost:3000/products?name=eq.Widget" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"price":21.00}'
```

> **On Windows with real curl flags:** use `curl.exe` instead of `curl` in PowerShell.

---

## Automated RBAC smoke test (PowerShell)

**File:** `db/scripts/smoke.ps1`  
**Purpose:** verifies RBAC and RLS end-to-end.

### What it checks

- Guest can read `/products`, cannot read `/orders`  
- User (`alice`/`1234`) only sees/creates **own** orders and lines  
- Admin (`admin`/`1234`) sees all orders and can update products  
- Uses `/rpc/login` to fetch JWTs and sends them as `Authorization: Bearer <token>`

### Run

From the `db` folder:
```powershell
pwsh ./scripts/smoke.ps1
```

Optional:
```powershell
# Hit a non-default URL
pwsh ./scripts/smoke.ps1 -BaseUrl "http://localhost:3000"
```

**Output:** section headers show each stage; it throws and stops on first failure.  
If all pass:
```
All checks passed
```

---

## PowerShell quick snippet (manual)

```powershell
$Base  = "http://localhost:3000"
$resp  = Invoke-RestMethod -Method Post "$Base/rpc/login" `
  -ContentType 'application/json' `
  -Body (@{identifier='alice'; pass='1234'} | ConvertTo-Json)
$TOKEN = ($resp.token) -replace "\\n","" -replace "`r","" -replace "`n",""
Invoke-RestMethod "$Base/orders" -Headers @{ Authorization = "Bearer $TOKEN" }
```

---

## Reset / Reseed

**Soft reseed** (re-run data script inside container):

```bash
docker compose exec -T db psql -U app -d appdb -v ON_ERROR_STOP=1 \
  -f /docker-entrypoint-initdb.d/02_seed_from_csv.sql
```

**Full reset:**
```bash
docker compose down -v
docker compose up -d
```

---

## Diagnostics

| Symptom / Error                               | Likely Cause                                   | Fix |
|-----------------------------------------------|------------------------------------------------|-----|
| `401 Unauthorized` / `Expected 3 parts in JWT`| Missing/invalid token                          | Re-login and pass `Authorization: Bearer <token>` |
| `PGRST301 No suitable key or wrong key type`  | JWT secret mismatch                             | Ensure compose `PGRST_JWT_SECRET` equals DB `app.jwt_secret` |
| `42501 permission denied`                     | RBAC / RLS blocked the operation               | Check `04_roles_rls.sql` policies and role grants |
| `503 Service Unavailable`                     | DB not ready                                    | Wait for healthcheck / restart |
| Schema/permissions not reflected              | PostgREST schema cache stale                    | `NOTIFY pgrst, 'reload schema';` in DB |

---

## Notes

- Login RPC: `POST /rpc/login` (body: `{"identifier":"<username or email>","pass":"<password>"}`)  
  returns `{"token":"<JWT>","role":"app_user|app_admin","user_id":<id>}`.
- RLS is enabled and **forced** on `orders` and `order_items`.  
- Helper SQL (`jwt_user_id()`, `jwt_role()`) read claims from the request.

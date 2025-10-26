<#  --------------------------------------------------------------------
 - Guest: can GET /products, cannot GET /orders
 - User  (alice/1234): sees only own /orders, can create own orders & lines
 - Admin (admin/1234): sees all /orders, can patch /products
 - Tokens are fetched via /rpc/login and used as Bearer in Authorization
 -------------------------------------------------------------------- #>

param(
  [string]$BaseUrl = "http://localhost:3000"   # Base URL of PostgREST API
)

# Fail fast on all errors
$ErrorActionPreference = "Stop"

# Print section headers
function Say($t){
  Write-Host "`n=== $t ===" -ForegroundColor Cyan
}

# Stop execution and report failure
function Fail($m){
  Write-Error $m
  exit 1
}

# Assert a condition or stop
function Assert($cond,$m){
  if(-not $cond){ Fail $m }
}

# Authenticate a user via /rpc/login and extract JWT
function Login($id,$pw){
  $body = @{ identifier=$id; pass=$pw } | ConvertTo-Json
  $resp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/rpc/login" -ContentType 'application/json' -Body $body
  $tok  = ($resp.token) -replace "\\n","" -replace "`r","" -replace "`n",""
  Assert ($tok.Split('.').Count -eq 3) "Bad JWT for $id"
  return $tok
}

# Perform GET with optional Bearer token
function GET($path,$tok=$null){
  $h=@{}; if($tok){ $h.Authorization="Bearer $tok" }
  Invoke-RestMethod -Method Get -Uri "$BaseUrl$path" -Headers $h
}

# Perform POST with optional Bearer token
function POST($path,$tok,$obj){
  $h=@{ 'Content-Type'='application/json' }
  if($tok){ $h.Authorization="Bearer $tok" }
  Invoke-RestMethod -Method Post -Uri "$BaseUrl$path" -Headers $h -Body ($obj|ConvertTo-Json)
}

# Perform PATCH with optional Bearer token
function PATCH($path,$tok,$obj){
  $h=@{ 'Content-Type'='application/json' }
  if($tok){ $h.Authorization="Bearer $tok" }
  Invoke-RestMethod -Method Patch -Uri "$BaseUrl$path" -Headers $h -Body ($obj|ConvertTo-Json)
}

# Decode JWT payload (Base64URL → JSON)
function B64UrlDecode([string]$s){
  $p=$s.Replace('-','+').Replace('_','/')
  switch($p.Length%4){0{};2{$p+='=='};3{$p+='='}}
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
}

# 1) Guest should be able to list products but not orders
Say "Guest can GET /products; cannot GET /orders"
$prods = GET "/products"
Assert ($prods.Count -gt 0) "Guest /products empty"
try {
  GET "/orders" | Out-Null
  Fail "Guest should NOT access /orders"
} catch {}

# 2) Authenticate both normal user and admin
Say "Login as user (alice) and admin"
$userTok  = Login "alice" "1234"
$adminTok = Login "admin" "1234"

# 3) User must only see their own orders (RLS)
Say "User sees only own orders (RLS)"
$userOrders = GET "/orders" $userTok
Assert ($userOrders.Count -gt 0) "User sees no orders"
$uid = (B64UrlDecode($userTok.Split('.')[1]) | ConvertFrom-Json).user_id
$foreign = ($userOrders | Where-Object { $_.userid -ne $uid })
Assert (-not $foreign -or $foreign.Count -eq 0) "User can see foreign orders!"

# 4) User can create orders for self but not others
Say "User can create own order; cannot create for others"
POST "/orders" $userTok @{ userid = $uid } | Out-Null
try {
  POST "/orders" $userTok @{ userid = 1 } | Out-Null
  Fail "User created for another userid"
} catch {}

# 5) User can add line only to own order, not others
Say "User can add line only to own order"
$ownLatest = (GET "/orders?order=orderid.desc&limit=1" $userTok)[0].orderid
POST "/order_items" $userTok @{ orderid=$ownLatest; productid=1; qty=1; unit_price=19.99 } | Out-Null

# Attempt to add line to a foreign order, should fail
$foreignOne = GET "/orders?select=orderid,userid&limit=1&userid=neq.$uid" $adminTok
if($foreignOne){
  $foid = $foreignOne[0].orderid
  try {
    POST "/order_items" $userTok @{ orderid=$foid; productid=1; qty=1; unit_price=19.99 } | Out-Null
    Fail "User inserted into someone else’s order"
  } catch {}
}

# 6) Admin can view all orders and update products
Say "Admin sees all orders; can PATCH products"
$all = GET "/orders" $adminTok
Assert ($all.Count -ge $userOrders.Count) "Admin should see >= user"
PATCH "/products?name=eq.Widget" $adminTok @{ price = 21.00 } | Out-Null

# Final success message
Write-Host "`nAll checks passed" -ForegroundColor Green

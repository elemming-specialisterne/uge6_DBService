/* ============================================================================
POST /rpc/login with JSON {identifier, pass} returns {token, role, user_id}.
- token is JWT signed with 'app.jwt_secret' (matches compose secret).
- role claim drives RLS: app_user or app_admin.
============================================================================ */

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- base64url without newlines
CREATE OR REPLACE FUNCTION public.base64url_encode(b bytea) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT rtrim(
           replace(
             replace(
               replace(encode($1,'base64'), E'\n',''),
             '+','-'),
           '/','_'),
         '=')
$$;

-- sign HS256
CREATE OR REPLACE FUNCTION public.jwt_sign_hs256(claims jsonb, secret text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  header text := '{"alg":"HS256","typ":"JWT"}';
  h64    text := public.base64url_encode(convert_to(header,'utf8'));
  p64    text := public.base64url_encode(convert_to(claims::text,'utf8'));
  data   text := h64 || '.' || p64;
  sig    text := public.base64url_encode(hmac(data, secret, 'sha256'));
BEGIN
  RETURN data || '.' || sig;
END$$;

-- set DB-side secret (must equal compose PGRST_JWT_SECRET)
DO $$
BEGIN
  PERFORM set_config('app.jwt_secret','superlong-32byte-min-secret-change-me', true);
  BEGIN
    EXECUTE format('ALTER DATABASE %I SET app.jwt_secret=%L', current_database(),
                   'superlong-32byte-min-secret-change-me');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM 1;
  END;
END$$;

-- RPC: issues JWTs
CREATE OR REPLACE FUNCTION public.login(identifier TEXT, pass TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  u RECORD;
  v_secret TEXT := current_setting('app.jwt_secret', true);
  v_claims JSONB;
  v_token  TEXT;
BEGIN
  SELECT userid, username, email, password_hash,
         CASE WHEN is_admin THEN 'app_admin' ELSE 'app_user' END AS db_role
  INTO u
  FROM public.users
  WHERE username = identifier OR email = identifier;

  IF NOT FOUND OR u.password_hash <> crypt(pass, u.password_hash) THEN
    RAISE EXCEPTION 'invalid_login' USING ERRCODE = '28P01';
  END IF;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE EXCEPTION 'jwt_secret_missing';
  END IF;

  v_claims := jsonb_build_object(
    'role',    u.db_role,
    'user_id', u.userid,
    'iat',     extract(epoch from now())::bigint,
    'exp',     extract(epoch from now() + interval '30 minutes')::bigint
  );

  v_token := public.jwt_sign_hs256(v_claims, v_secret);
  RETURN jsonb_build_object('token', v_token, 'role', u.db_role, 'user_id', u.userid);
END$$;

REVOKE ALL ON FUNCTION public.login(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.login(TEXT, TEXT) TO web_anon;

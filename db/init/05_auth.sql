-- read env from container
\getenv dbname POSTGRES_DB
\getenv jwt    JWT_SECRET

-- ensure roles exist before any GRANTs
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='web_anon') THEN CREATE ROLE web_anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_user') THEN CREATE ROLE app_user NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='admin') THEN CREATE ROLE admin NOINHERIT; END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
ALTER DATABASE :"dbname" SET app.jwt_secret = :'jwt';

CREATE SCHEMA IF NOT EXISTS auth;

CREATE OR REPLACE FUNCTION auth.b64url(in_bytes bytea)
RETURNS text LANGUAGE sql AS
$$ SELECT translate(encode($1,'base64'), E'+/=\n', '-_') $$;

CREATE OR REPLACE FUNCTION auth.jwt_sign(payload jsonb)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  header_b64  text := auth.b64url(convert_to('{"alg":"HS256","typ":"JWT"}','utf8'));
  payload_b64 text := auth.b64url(convert_to(payload::text,'utf8'));
  to_sign     text := header_b64 || '.' || payload_b64;
  sig_b64     text := auth.b64url(
                        hmac(convert_to(to_sign,'utf8'),
                             convert_to(current_setting('app.jwt_secret'),'utf8'),
                             'sha256'));
BEGIN
  RETURN to_sign || '.' || sig_b64;
END $$;

-- SECURITY DEFINER so web_anon can call through to read public."user"
CREATE OR REPLACE FUNCTION auth.login(p_username text, p_password text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  u RECORD;
  tok text;
  role_claim text;
BEGIN
  SELECT userid, username, password_hash, role_name
  INTO   u
  FROM   "users"
  WHERE  username = p_username;

  IF u IS NULL OR NOT crypt(p_password, u.password_hash) = u.password_hash THEN
    RAISE EXCEPTION 'invalid credentials' USING ERRCODE='28000';
  END IF;

  role_claim := CASE WHEN lower(coalesce(u.role_name,'')) = 'admin'
                     THEN 'admin' ELSE 'app_user' END;

  tok := auth.jwt_sign(jsonb_build_object(
           'role',    role_claim,
           'user_id', u.userid,
           'exp',     extract(epoch FROM now())::int + 3600
         ));
  RETURN jsonb_build_object('token', tok);
END $$;

GRANT USAGE ON SCHEMA auth TO web_anon;
GRANT EXECUTE ON FUNCTION auth.login(text,text) TO web_anon;

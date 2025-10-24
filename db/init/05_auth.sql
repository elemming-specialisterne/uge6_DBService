-- 05_auth.sql
-- no: CREATE EXTENSION pgjwt;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER DATABASE shop SET app.jwt_secret = 'vK/5XZDYyHyggZ1GMk232JSAz42tq55mNM/0CoXIfa2hcfsKKuB1rNW8yiInSvQZ';

CREATE SCHEMA IF NOT EXISTS auth;

CREATE OR REPLACE FUNCTION auth.b64url(in_bytes bytea) RETURNS text LANGUAGE sql AS
$$ SELECT translate(encode($1,'base64'), E'+/=\n', '-_') $$;

CREATE OR REPLACE FUNCTION auth.jwt_sign(payload jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  header_b64 text := auth.b64url(convert_to('{"alg":"HS256","typ":"JWT"}','utf8'));
  payload_b64 text := auth.b64url(convert_to(payload::text,'utf8'));
  to_sign text := header_b64 || '.' || payload_b64;
  sig_b64 text := auth.b64url(hmac(convert_to(to_sign,'utf8'),
                                   convert_to(current_setting('app.jwt_secret'),'utf8'),
                                   'sha256'));
BEGIN
  RETURN to_sign || '.' || sig_b64;
END $$;

CREATE OR REPLACE FUNCTION auth.login(p_username text, p_password text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u RECORD; tok text;
BEGIN
  SELECT userid, username, role_name, password_hash INTO u FROM users WHERE username = p_username;
  IF u IS NULL OR NOT crypt(p_password, u.password_hash) = u.password_hash THEN
    RAISE EXCEPTION 'invalid credentials' USING ERRCODE='28000';
  END IF;

  tok := auth.jwt_sign(jsonb_build_object(
    'role', u.role_name,
    'user_id', u.userid,
    'exp', extract(epoch FROM now())::int + 3600
  ));
  RETURN jsonb_build_object('token', tok);
END $$;

-- allow anon to call /rpc/login
GRANT USAGE ON SCHEMA auth TO web_anon;
GRANT EXECUTE ON FUNCTION auth.login(text,text) TO web_anon;

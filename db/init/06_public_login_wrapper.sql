-- 06_public_login_wrapper.sql
-- Exposes the auth.login() function to PostgREST via /rpc/login endpoint
-- Keeps all logic inside the auth schema but callable from the public schema.

-- Ensure dependencies
CREATE SCHEMA IF NOT EXISTS auth;

-- Wrapper function
CREATE OR REPLACE FUNCTION public.login(p_username text, p_password text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.login(p_username, p_password);
$$;

-- Restrict execution to web_anon
GRANT EXECUTE ON FUNCTION public.login(text, text) TO web_anon;
REVOKE EXECUTE ON FUNCTION public.login(text, text) FROM PUBLIC;

-- Optional: reload schema if already running
-- NOTIFY pgrst, 'reload schema';

-- /rpc/login available even if only 'public' is exposed
CREATE OR REPLACE FUNCTION public.login(p_username text, p_password text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$ SELECT auth.login(p_username, p_password) $$;

-- allow anonymous to call it
GRANT EXECUTE ON FUNCTION public.login(text,text) TO web_anon;
REVOKE EXECUTE ON FUNCTION public.login(text,text) FROM PUBLIC;

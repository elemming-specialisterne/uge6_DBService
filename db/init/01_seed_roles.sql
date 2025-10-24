-- ./db/init/01_seed_roles.sql
-- Create database roles used by PostgREST tokens. Grants are in 07_acl.sql.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_user') THEN
    CREATE ROLE app_user NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='admin') THEN
    CREATE ROLE admin NOINHERIT;
  END IF;
END $$;

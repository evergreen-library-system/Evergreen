-- Rather than polluting the public schema with general Evergreen
-- functions, carve out a dedicated schema

DROP SCHEMA IF EXISTS evergreen CASCADE;

BEGIN;

CREATE SCHEMA evergreen;

CREATE OR REPLACE FUNCTION evergreen.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.change_db_setting(setting_name TEXT, settings TEXT[]) RETURNS VOID AS $$
BEGIN
EXECUTE 'ALTER DATABASE ' || quote_ident(current_database()) || ' SET ' || quote_ident(setting_name) || ' = ' || array_to_string(settings, ',');
END;
$$ LANGUAGE plpgsql;

SELECT evergreen.change_db_setting('search_path', ARRAY['public','pg_catalog']);

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0500');

CREATE OR REPLACE FUNCTION evergreen.change_db_setting(setting_name TEXT, settings TEXT[]) RETURNS VOID AS $$
BEGIN
EXECUTE 'ALTER DATABASE ' || quote_ident(current_database()) || ' SET ' || quote_ident(setting_name) || ' = ' || array_to_string(settings, ',');
END;
$$ LANGUAGE plpgsql;

SELECT evergreen.change_db_setting('search_path', ARRAY['public','pg_catalog']);

COMMIT;

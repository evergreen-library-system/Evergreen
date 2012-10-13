BEGIN;

-- stop on error
\set ON_ERROR_STOP on

-- build functions, tables
\i env_create.sql

-- load concerto bibs
\i bibs_concerto.sql

-- insert all loaded bibs into the biblio.record_entry
INSERT INTO biblio.record_entry (marc, last_xact_id) 
    SELECT marc, tag FROM marcxml_import ORDER BY id;

-- load concerto copies, etc.
\i assets_concerto.sql

-- clean up the env
\i env_destroy.sql

COMMIT;

BEGIN;

-- stop on error
\set ON_ERROR_STOP on

-- build functions, tables
\i env_create.sql

-- load concerto bibs
\i bibs_concerto.sql

-- load french bibs
\i bibs_fre.sql 

-- load map bibs
\i bibs_maps.sql 

-- load graphic 880 field bibs
\i bibs_graphic_880.sql 

-- insert all loaded bibs into the biblio.record_entry in insert order
INSERT INTO biblio.record_entry (marc, last_xact_id) 
    SELECT marc, tag FROM marcxml_import ORDER BY id;

-- load concerto copies, etc.
\i assets_concerto.sql

-- load french copies, etc.
\i assets_fre.sql

-- load graphic 880 field copies, etc
\i assets_graphic_880.sql 

-- load sample patrons
\i users_patrons_100.sql

-- load sample staff users
\i users_staff_134.sql

-- circs, etc.
\i transactions.sql

-- clean up the env
\i env_destroy.sql

COMMIT;

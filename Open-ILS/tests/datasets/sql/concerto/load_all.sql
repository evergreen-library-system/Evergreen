BEGIN;

-- stop on error
\set ON_ERROR_STOP on

-- build functions, tables
\i env_create.sql

-- load libraries (org unit)
\i libraries.sql

-- load concerto authorities
\i auth_concerto.sql

-- load concerto bibs
\i bibs_concerto.sql

-- load french bibs
\i bibs_fre.sql 

-- load map bibs
\i bibs_maps.sql 

-- load graphic 880 field bibs
\i bibs_graphic_880.sql 

-- load fiction bibs
\i bibs_fic.sql

-- load RDA bibs
\i bibs_rda.sql

-- load LC authorities
\i auth_lc.sql

-- load MeSH authorities
\i auth_mesh.sql

-- insert all loaded bibs into the biblio.record_entry in insert order
INSERT INTO biblio.record_entry (marc, last_xact_id) 
    SELECT marc, tag FROM marcxml_import ORDER BY id;

-- load concerto copies, etc.
\i assets_concerto.sql

-- load french copies, etc.
\i assets_fre.sql

-- load graphic 880 field copies, etc
\i assets_graphic_880.sql 

-- load fiction copies, etc.
\i assets_fic.sql

-- load RDA copies, etc.
\i assets_rda.sql

-- load copy-related data
\i assets_extras.sql

-- load sample patrons
\i users_patrons_100.sql

-- load sample staff users
\i users_staff_134.sql

-- circs, etc.
\i transactions.sql
\i neg_bal_custom_transactions.sql

-- funds, orders, etc.
\i acq.sql

-- delete previously imported bibs
DELETE FROM marcxml_import;

-- load EbookAPI bibs
\i bibs_ebook_api.sql

-- load metarecord bibs
\i bibs_mr.sql

-- load booking bibs
\i bibs_booking.sql

-- load Czech bibs
\i bibs_cze.sql

-- load e-textbook bibs (to attach to courses in the course module)
\i bibs_etextbooks.sql

-- insert all loaded bibs into the biblio.record_entry in insert order
INSERT INTO biblio.record_entry (marc, last_xact_id)
    SELECT marc, tag FROM marcxml_import ORDER BY id;

-- load MR copies, etc.
\i assets_mr.sql

-- load booking assets
\i assets_booking.sql

-- load Czech assets
\i assets_cze.sql

-- load booking resource types and resources
\i booking_resources_types.sql

-- load survey data
\i surveys.sql

-- load remoteauth data
\i remoteauth.sql

-- load course materials data
\i course_materials.sql

-- clean up the env
\i env_destroy.sql

COMMIT;

SELECT actor.change_password(id, 'demo123') FROM actor.usr WHERE id > 1;

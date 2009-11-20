BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0088'); -- dbs

-- Take advantage of the "IF EXISTS" option that has existed since
-- PostgreSQL 8.2 to avoid SQL errors 
CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DROP TRIGGER IF EXISTS zzz_update_materialized_simple_record_tgr ON metabib.real_full_rec;
$$ LANGUAGE SQL;

COMMIT;

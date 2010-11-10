BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0462'); -- gmc

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    DELETE FROM reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER zzz_update_materialized_simple_record_tgr
        AFTER INSERT OR UPDATE OR DELETE ON metabib.real_full_rec
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_sync();

$$ LANGUAGE SQL;

COMMIT;

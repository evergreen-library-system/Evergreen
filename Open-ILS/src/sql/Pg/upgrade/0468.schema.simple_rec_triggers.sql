BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0468'); -- gmc

DROP TRIGGER IF EXISTS zzz_update_materialized_simple_record_tgr ON metabib.real_full_rec;
DROP TRIGGER IF EXISTS zzz_update_materialized_simple_rec_delete_tgr ON biblio.record_entry;
DROP TRIGGER IF EXISTS bbb_simple_rec_trigger ON biblio.record_entry;

DROP FUNCTION IF EXISTS reporter.simple_rec_sync();
DROP FUNCTION IF EXISTS reporter.simple_rec_bib_sync();

CREATE TRIGGER bbb_simple_rec_trigger
    AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry
    FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger();

CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DROP TRIGGER IF EXISTS bbb_simple_rec_trigger ON biblio.record_entry;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    DELETE FROM reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER bbb_simple_rec_trigger
        AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger();

$$ LANGUAGE SQL;

COMMIT;

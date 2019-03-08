BEGIN;

SELECT evergreen.upgrade_deps_block_check('1155', :eg_version);

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    TRUNCATE TABLE reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER bbb_simple_rec_trigger
        AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger();

$$ LANGUAGE SQL;


COMMIT;


BEGIN;

CREATE TABLE reporter.materialized_simple_record AS SELECT * FROM reporter.simple_record WHERE 1=0;

INSERT INTO reporter.materialized_simple_record
    (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
    SELECT DISTINCT ON (id) * FROM reporter.super_simple_record;

ALTER TABLE reporter.materialized_simple_record ADD PRIMARY KEY (id);

CREATE OR REPLACE FUNCTION reporter.simple_rec_sync () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN
        DELETE FROM reporter.materialized_simple_record WHERE id = OLD.record;
    END IF;

    IF TG_OP IN ('INSERT','UPDATE') AND NOT NEW.deleted THEN
        INSERT INTO reporter.materialized_simple_record SELECT * FROM reporter.simple_record WHERE id = NEW.record;
    END IF;

END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER zzz_update_materialized_simple_record_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.full_rec
    FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_sync();

COMMIT;


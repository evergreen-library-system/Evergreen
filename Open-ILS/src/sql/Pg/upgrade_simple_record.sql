
BEGIN;

CREATE TABLE reporter.materialized_simple_record AS SELECT * FROM reporter.super_simple_record WHERE 1=0;

INSERT INTO reporter.materialized_simple_record
    (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
    SELECT DISTINCT ON (id) * FROM reporter.super_simple_record;

ALTER TABLE reporter.materialized_simple_record ADD PRIMARY KEY (id);

CREATE OR REPLACE VIEW reporter.super_simple_record AS SELECT * FROM reporter.materialized_simple_record;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    title.value AS title,
    FIRST(author.value) AS author,
    publisher.value AS publisher,
    SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
    ARRAY_ACCUM( SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
    ARRAY_ACCUM( SUBSTRING(issn.value FROM $$^\S+$$) ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,8,9;

CREATE OR REPLACE FUNCTION reporter.simple_rec_sync () RETURNS TRIGGER AS $$
DECLARE
    r_id        BIGINT;
    new_data    RECORD;
BEGIN
    IF TG_OP IN ('DELETE') THEN
        r_id := OLD.record;
    ELSE
        r_id := NEW.record;
    END IF;

    SELECT * INTO new_data FROM reporter.materialized_simple_record WHERE id = r_id FOR UPDATE;
    DELETE FROM reporter.materialized_simple_record WHERE id = r_id;

    IF TG_OP IN ('DELETE') THEN
        RETURN OLD;
    ELSE
        INSERT INTO reporter.materialized_simple_record SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record WHERE id = NEW.record;
        RETURN NEW;
    END IF;

END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER zzz_update_materialized_simple_record_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.full_rec
    FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_sync();

COMMIT;


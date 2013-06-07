BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('0796', :eg_version); -- berick/dbwells

ALTER TABLE vandelay.bib_queue ADD COLUMN match_bucket
   INTEGER REFERENCES container.biblio_record_entry_bucket(id)
   ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;  

CREATE OR REPLACE FUNCTION vandelay.match_bib_record() RETURNS TRIGGER AS $func$
DECLARE
    incoming_existing_id    TEXT;
    test_result             vandelay.match_set_test_result%ROWTYPE;
    tmp_rec                 BIGINT;
    match_set               INT;
    match_bucket            INT;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT q.match_set INTO match_set FROM vandelay.bib_queue q WHERE q.id = NEW.queue;

    IF match_set IS NOT NULL THEN
        NEW.quality := vandelay.measure_record_quality( NEW.marc, match_set );
    END IF;

    -- Perfect matches on 901$c exit early with a match with high quality.
    incoming_existing_id :=
        oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]', NEW.marc);

    IF incoming_existing_id IS NOT NULL AND incoming_existing_id != '' THEN
        SELECT id INTO tmp_rec FROM biblio.record_entry WHERE id = incoming_existing_id::bigint;
        IF tmp_rec IS NOT NULL THEN
            INSERT INTO vandelay.bib_match (queued_record, eg_record, match_score, quality) 
                SELECT
                    NEW.id, 
                    b.id,
                    9999,
                    -- note: no match_set means quality==0
                    vandelay.measure_record_quality( b.marc, match_set )
                FROM biblio.record_entry b
                WHERE id = incoming_existing_id::bigint;
        END IF;
    END IF;

    IF match_set IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT q.match_bucket INTO match_bucket FROM vandelay.bib_queue q WHERE q.id = NEW.queue;

    FOR test_result IN SELECT * FROM
        vandelay.match_set_test_marcxml(match_set, NEW.marc, match_bucket) LOOP

        INSERT INTO vandelay.bib_match ( queued_record, eg_record, match_score, quality )
            SELECT  
                NEW.id,
                test_result.record,
                test_result.quality,
                vandelay.measure_record_quality( b.marc, match_set )
	        FROM  biblio.record_entry b
	        WHERE id = test_result.record;

    END LOOP;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS vandelay.match_set_test_marcxml(INTEGER, TEXT);

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT, bucket_id INTEGER 
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    svf_rstore  HSTORE;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);
    svf_rstore := vandelay.extract_rec_attrs(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(match_set_id, tags_rstore);

    query_ := 'SELECT DISTINCT(record), ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT ARRAY_TO_STRING(
        ARRAY_ACCUM('COALESCE(n' || q::TEXT || '.quality, 0)'), ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT ARRAY_TO_STRING(ARRAY_ACCUM(j), E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n';

    -- join the record bucket
    IF bucket_id IS NOT NULL THEN
        query_ := query_ || 'JOIN container.biblio_record_entry_bucket_item ' ||
            'brebi ON (brebi.target_biblio_record_entry = record ' ||
            'AND brebi.bucket = ' || bucket_id || E')\n';
    END IF;

    query_ := query_ || 'JOIN biblio.record_entry bre ON (bre.id = record) ' || 'WHERE ' || wq || ' AND not bre.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore, svf_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

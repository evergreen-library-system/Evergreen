-- Evergreen DB patch 0598.schema.vandelay_one_match_per.sql
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0598', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT
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
    wq := vandelay.get_expr_from_match_set(match_set_id);

    query_ := 'SELECT DISTINCT(bre.id) AS record, ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT ARRAY_TO_STRING(
        ARRAY_ACCUM('COALESCE(n' || q::TEXT || '.quality, 0)'), ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n' ||
        'FROM biblio.record_entry bre ';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT ARRAY_TO_STRING(ARRAY_ACCUM(j), E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n' || 'WHERE ' || wq || ' AND not bre.deleted';

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

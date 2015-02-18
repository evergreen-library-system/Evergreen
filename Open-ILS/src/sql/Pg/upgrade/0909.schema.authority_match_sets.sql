BEGIN;

SELECT evergreen.upgrade_deps_block_check('0909', :eg_version);

ALTER TABLE vandelay.authority_match
    ADD COLUMN match_score INT NOT NULL DEFAULT 0;

-- support heading=TRUE match set points
ALTER TABLE vandelay.match_set_point
    ADD COLUMN heading BOOLEAN NOT NULL DEFAULT FALSE,
    DROP CONSTRAINT vmsp_need_a_tag_or_a_ff_or_a_bo,
    ADD CONSTRAINT vmsp_need_a_tag_or_a_ff_or_a_heading_or_a_bo
    CHECK (
        (tag IS NOT NULL AND svf IS NULL AND heading IS FALSE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NOT NULL AND heading IS FALSE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NULL AND heading IS TRUE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NULL AND heading IS FALSE AND bool_op IS NOT NULL)
    );

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS TEXT AS $$
DECLARE
    root vandelay.match_set_point;
BEGIN
    SELECT * INTO root FROM vandelay.match_set_point
        WHERE parent IS NULL AND match_set = match_set_id;

    RETURN vandelay.get_expr_from_match_set_point(
        root, tags_rstore, auth_heading);
END;
$$  LANGUAGE PLPGSQL;

-- backwards compat version so we don't have 
-- to modify vandelay.match_set_test_marcxml()
CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE
) RETURNS TEXT AS $$
BEGIN
    RETURN vandelay.get_expr_from_match_set(
        match_set_id, tags_rstore, NULL);
END;
$$  LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS 
    vandelay.get_expr_from_match_set_point(vandelay.match_set_point, HSTORE);

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS TEXT AS $$
DECLARE
    q           TEXT;
    i           INTEGER;
    this_op     TEXT;
    children    INTEGER[];
    child       vandelay.match_set_point;
BEGIN
    SELECT ARRAY_AGG(id) INTO children FROM vandelay.match_set_point
        WHERE parent = node.id;

    IF ARRAY_LENGTH(children, 1) > 0 THEN
        this_op := vandelay._get_expr_render_one(node);
        q := '(';
        i := 1;
        WHILE children[i] IS NOT NULL LOOP
            SELECT * INTO child FROM vandelay.match_set_point
                WHERE id = children[i];
            IF i > 1 THEN
                q := q || ' ' || this_op || ' ';
            END IF;
            i := i + 1;
            q := q || vandelay.get_expr_from_match_set_point(
                child, tags_rstore, auth_heading);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node, tags_rstore, auth_heading);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS 
    vandelay._get_expr_push_jrow(vandelay.match_set_point, HSTORE);

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
    jrow_count  INT;
    my_using    TEXT;
    my_join     TEXT;
    rec_table   TEXT;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore
    -- a non-NULL auth_heading means we're matching authority records

    IF auth_heading IS NOT NULL THEN
        rec_table := 'authority.full_rec';
    ELSE
        rec_table := 'metabib.full_rec';
    END IF;

    caseless := FALSE;
    SELECT COUNT(*) INTO jrow_count FROM _vandelay_tmp_jrows;
    IF jrow_count > 0 THEN
        my_using := ' USING (record)';
        my_join := 'FULL OUTER JOIN';
    ELSE
        my_using := '';
        my_join := 'FROM';
    END IF;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    IF node.negate THEN
        IF caseless THEN
            op := 'NOT LIKE';
        ELSE
            op := '<>';
        END IF;
    ELSE
        IF caseless THEN
            op := 'LIKE';
        ELSE
            op := '=';
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := my_join || ' (SELECT *, ';
    IF node.tag IS NOT NULL THEN
        jrow := jrow  || node.quality ||
            ' AS quality FROM ' || rec_table || ' mfr WHERE mfr.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND mfr.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';
        jrow := jrow || vandelay._node_tag_comparisons(caseless, op, tags_rstore, tagkey);
        jrow := jrow || ')) ' || my_alias || my_using || E'\n';
    ELSE    -- svf
        IF auth_heading IS NOT NULL THEN -- authority record
            IF node.heading AND auth_heading <> '' THEN
                jrow := jrow || 'id AS record, ' || node.quality ||
                ' AS quality FROM authority.record_entry are ' ||
                ' WHERE are.heading = ''' || auth_heading || '''';
                jrow := jrow || ') ' || my_alias || my_using || E'\n';
            END IF;
        ELSE -- bib record
            jrow := jrow || 'id AS record, ' || node.quality ||
                ' AS quality FROM metabib.record_attr_flat mraf WHERE mraf.attr = ''' ||
                node.svf || ''' AND mraf.value ' || op || ' $2->''' || node.svf || ''') ' ||
                my_alias || my_using || E'\n';
        END IF;
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.match_set_test_authxml(
    match_set_id INTEGER, record_xml TEXT
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    heading     TEXT;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);

    SELECT normalize_heading INTO heading 
        FROM authority.normalize_heading(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(
        match_set_id, tags_rstore, heading);

    query_ := 'SELECT DISTINCT(record), ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT STRING_AGG(
        'COALESCE(n' || q::TEXT || '.quality, 0)', ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT STRING_AGG(j, E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n';

    query_ := query_ || 'JOIN authority.record_entry are ON (are.id = record) ' 
        || 'WHERE ' || wq || ' AND not are.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.measure_auth_record_quality 
    ( xml TEXT, match_set_id INT ) RETURNS INT AS $_$
DECLARE
    out_q   INT := 0;
    rvalue  TEXT;
    test    vandelay.match_set_quality%ROWTYPE;
BEGIN

    FOR test IN SELECT * FROM vandelay.match_set_quality 
            WHERE match_set = match_set_id LOOP
        IF test.tag IS NOT NULL THEN
            FOR rvalue IN SELECT value FROM vandelay.flatten_marc( xml ) 
                WHERE tag = test.tag AND subfield = test.subfield LOOP
                IF test.value = rvalue THEN
                    out_q := out_q + test.quality;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    RETURN out_q;
END;
$_$ LANGUAGE PLPGSQL;



CREATE OR REPLACE FUNCTION vandelay.match_authority_record() RETURNS TRIGGER AS $func$
DECLARE
    incoming_existing_id    TEXT;
    test_result             vandelay.match_set_test_result%ROWTYPE;
    tmp_rec                 BIGINT;
    match_set               INT;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.authority_match WHERE queued_record = NEW.id;

    SELECT q.match_set INTO match_set FROM vandelay.authority_queue q WHERE q.id = NEW.queue;

    IF match_set IS NOT NULL THEN
        NEW.quality := vandelay.measure_auth_record_quality( NEW.marc, match_set );
    END IF;

    -- Perfect matches on 901$c exit early with a match with high quality.
    incoming_existing_id :=
        oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]', NEW.marc);

    IF incoming_existing_id IS NOT NULL AND incoming_existing_id != '' THEN
        SELECT id INTO tmp_rec FROM authority.record_entry WHERE id = incoming_existing_id::bigint;
        IF tmp_rec IS NOT NULL THEN
            INSERT INTO vandelay.authority_match (queued_record, eg_record, match_score, quality) 
                SELECT
                    NEW.id, 
                    b.id,
                    9999,
                    -- note: no match_set means quality==0
                    vandelay.measure_auth_record_quality( b.marc, match_set )
                FROM authority.record_entry b
                WHERE id = incoming_existing_id::bigint;
        END IF;
    END IF;

    IF match_set IS NULL THEN
        RETURN NEW;
    END IF;

    FOR test_result IN SELECT * FROM
        vandelay.match_set_test_authxml(match_set, NEW.marc) LOOP

        INSERT INTO vandelay.authority_match ( queued_record, eg_record, match_score, quality )
            SELECT  
                NEW.id,
                test_result.record,
                test_result.quality,
                vandelay.measure_auth_record_quality( b.marc, match_set )
	        FROM  authority.record_entry b
	        WHERE id = test_result.record;

    END LOOP;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER zz_match_auths_trigger
    BEFORE INSERT OR UPDATE ON vandelay.queued_authority_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.match_authority_record();

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_record_with_best ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    lwm_ratio_value NUMERIC;
BEGIN

    lwm_ratio_value := COALESCE(lwm_ratio_value_p, 0.0);

    PERFORM * FROM vandelay.queued_authority_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.authority_match m
            JOIN vandelay.queued_authority_record qr ON (m.queued_record = qr.id)
            JOIN vandelay.authority_queue q ON (qr.queue = q.id)
            JOIN authority.record_entry r ON (r.id = m.eg_record)
      WHERE m.queued_record = import_id
            AND qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC >= lwm_ratio_value
      ORDER BY  m.match_score DESC, -- required match score
                qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC DESC, -- quality tie breaker
                m.id -- when in doubt, use the first match
      LIMIT 1;

    IF eg_id IS NULL THEN
        -- RAISE NOTICE 'incoming record is not of high enough quality';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_authority_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;


COMMIT;

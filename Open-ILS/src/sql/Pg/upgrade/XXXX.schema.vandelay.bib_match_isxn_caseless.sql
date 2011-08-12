-- Evergreen DB patch XXXX.schema.vandelay.bib_match_isxn_caseless.sql

BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX metabib_full_rec_isxn_caseless_idx
    ON metabib.real_full_rec (LOWER(value))
    WHERE tag IN ('020', '022', '024');


CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_ACCUM(tag || (COALESCE(subfield, ''))),
            ARRAY_ACCUM(value)
        )
        FROM (
            SELECT
                tag, subfield,
                CASE WHEN tag IN ('020', '022', '024') THEN  -- caseless
                    ARRAY_ACCUM(LOWER(value))::TEXT
                ELSE
                    ARRAY_ACCUM(value)::TEXT
                END AS value
                FROM vandelay.flatten_marc(record_xml)
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore

    IF node.negate THEN
        op := '<>';
    ELSE
        op := '=';
    END IF;

    caseless := FALSE;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := 'LEFT JOIN (SELECT *, ' || node.quality ||
        ' AS quality FROM metabib.';
    IF node.tag IS NOT NULL THEN
        jrow := jrow || 'full_rec) ' || my_alias || ' ON (' ||
            my_alias || '.record = bre.id AND ' || my_alias || '.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND ' || my_alias || '.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';

        IF caseless THEN
            jrow := jrow || 'LOWER(' || my_alias || '.value) ' || op;
        ELSE
            jrow := jrow || my_alias || '.value ' || op;
        END IF;

        jrow := jrow || ' ANY(($1->''' || tagkey || ''')::TEXT[])))';
    ELSE    -- svf
        jrow := jrow || 'record_attr) ' || my_alias || ' ON (' ||
            my_alias || '.id = bre.id AND (' ||
            my_alias || '.attrs->''' || node.svf ||
            ''' ' || op || ' $2->''' || node.svf || '''))';
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

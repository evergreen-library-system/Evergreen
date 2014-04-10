BEGIN;

SELECT evergreen.upgrade_deps_block_check('0879', :eg_version);

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point,
    tags_rstore HSTORE
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
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore

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
            ' AS quality FROM metabib.full_rec mfr WHERE mfr.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND mfr.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';
        jrow := jrow || vandelay._node_tag_comparisons(caseless, op, tags_rstore, tagkey);
        jrow := jrow || ')) ' || my_alias || my_using || E'\n';
    ELSE    -- svf
        jrow := jrow || 'id AS record, ' || node.quality ||
            ' AS quality FROM metabib.record_attr_flat mraf WHERE mraf.attr = ''' ||
            node.svf || ''' AND mraf.value ' || op || ' $2->''' || node.svf || ''') ' ||
            my_alias || my_using || E'\n';
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;

COMMIT;


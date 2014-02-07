-- Compiled list of all changed functions and views where we went from:
--   array_accum() to array_agg()
--   array_to_string(array_agg()) to string_agg()

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0855', :eg_version);

-- from 000.functions.general.sql

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT) RETURNS anyarray AS $$ SELECT ARRAY_AGG(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2; $$ LANGUAGE SQL;


-- from 002.functions.config.sql

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(string_agg(output,' '),$4,'','g') FROM oils_xpath_table('id', 'marc', $1, $3, 'id='||$2)x(id INT, output TEXT);
$$ LANGUAGE SQL;


-- from 011.schema.authority.sql

CREATE OR REPLACE FUNCTION authority.axis_authority_tags(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(field) FROM authority.browse_axis_authority_field_map WHERE axis = $1;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.axis_authority_tags_refs(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
       SELECT  unnest(ARRAY_CAT(
                 ARRAY[a.field],
                 (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.field)
             )) y
       FROM  authority.browse_axis_authority_field_map a
       WHERE axis = $1) x
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(authority_field) FROM authority.control_set_bib_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags_refs(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.authority_field],
                    (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.authority_field)
                )) y
      FROM  authority.control_set_bib_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(id) FROM authority.control_set_authority_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags_refs(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.id],
                    (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.id)
                )) y
      FROM  authority.control_set_authority_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;


-- from 012.schema.vandelay.sql

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT, attr_defs TEXT[]) RETURNS hstore AS $_$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE name IN (SELECT * FROM UNNEST(attr_defs)) ORDER BY format LOOP

        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  STRING_AGG(x.value, COALESCE(attr_def.joiner,' ')) INTO attr_value
              FROM  vandelay.flatten_marc(xml) AS x
              WHERE x.tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL
                            THEN POSITION(x.subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                        END
              GROUP BY x.tag
              ORDER BY x.tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field(xml, attr_def.fixed_field);

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(xml,xfrm.xslt);
                ELSE
                    transformed_xml := xml;
                END IF;

                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  m.value::TEXT INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(xml) v
                    JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf
              LIMIT 1; -- Just in case ...

        END IF;

        -- apply index normalizers to attr_value
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
              WHERE attr = attr_def.name
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_nullable( attr_value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO attr_value;

        END LOOP;

        -- Add the new value to the hstore
        new_attrs := new_attrs || hstore( attr_def.name, attr_value );

    END LOOP;

    RETURN new_attrs;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT ) RETURNS hstore AS $_$
    SELECT vandelay.extract_rec_attrs( $1, (SELECT ARRAY_AGG(name) FROM config.record_attr_definition));
$_$ LANGUAGE SQL;

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

CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $func$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_AGG(tag || (COALESCE(subfield, ''))),
            ARRAY_AGG(value)
        )
        FROM (
            SELECT  tag, subfield, ARRAY_AGG(value)::TEXT AS value
              FROM  (SELECT tag,
                            subfield,
                            CASE WHEN tag = '020' THEN -- caseless -- isbn
                                LOWER((REGEXP_MATCHES(value,$$^(\S{10,17})$$))[1] || '%')
                            WHEN tag = '022' THEN -- caseless -- issn
                                LOWER((REGEXP_MATCHES(value,$$^(\S{4}[- ]?\S{4})$$))[1] || '%')
                            WHEN tag = '024' THEN -- caseless -- upc (other)
                                LOWER(value || '%')
                            ELSE
                                value
                            END AS value
                      FROM  vandelay.flatten_marc(record_xml)) x
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point,
    tags_rstore HSTORE
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
            q := q || vandelay.get_expr_from_match_set_point(child, tags_rstore);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node, tags_rstore);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;


-- from 030.schema.metabib.sql

CREATE OR REPLACE FUNCTION biblio.extract_located_uris( bib_id BIGINT, marcxml TEXT, editor_id INT ) RETURNS VOID AS $func$
DECLARE
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner_list  TEXT[];
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;
BEGIN

    -- Clear any URI mappings and call numbers for this bib.
    -- This leads to acn / auricnm inflation, but also enables
    -- old acn/auricnm's to go away and for bibs to be deleted.
    FOR uri_cn_id IN SELECT id FROM asset.call_number WHERE record = bib_id AND label = '##URI##' AND NOT deleted LOOP
        DELETE FROM asset.uri_call_number_map WHERE call_number = uri_cn_id;
        DELETE FROM asset.call_number WHERE id = uri_cn_id;
    END LOOP;

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()',uri_xml))[1];
            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];

            IF uri_label IS NULL THEN
                uri_label := uri_href;
            END IF;
            CONTINUE WHEN uri_href IS NULL;

            -- Get the distinct list of libraries wanting to use 
            SELECT  ARRAY_AGG(
                        DISTINCT REGEXP_REPLACE(
                            x,
                            $re$^.*?\((\w+)\).*$$re$,
                            E'\\1'
                        )
                    ) INTO uri_owner_list
              FROM  UNNEST(
                        oils_xpath(
                            '//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',
                            uri_xml
                        )
                    )x;

            IF ARRAY_UPPER(uri_owner_list,1) > 0 THEN

                -- look for a matching uri
                IF uri_use IS NULL THEN
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active;
                    END IF;
                ELSE
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                    END IF;
                END IF;

                FOR j IN 1 .. ARRAY_UPPER(uri_owner_list, 1) LOOP
                    uri_owner := uri_owner_list[j];

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
                    CONTINUE WHEN NOT FOUND;

                    -- we need a call number to link through
                    SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    IF NOT FOUND THEN
                        INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                            VALUES (uri_owner_id, bib_id, 'now', 'now', editor_id, editor_id, '##URI##');
                        SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    END IF;

                    -- now, link them if they're not already
                    SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    IF NOT FOUND THEN
                        INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
                    END IF;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;
        IF NOT FOUND THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id;
            DELETE FROM metabib.record_attr WHERE id = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  STRING_AGG(value, COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  m.value INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id) v
                            JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
                      WHERE v.subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            COALESCE( quote_literal( attr_value ), 'NULL' ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                DELETE FROM metabib.record_attr WHERE id = NEW.id;
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


-- from 100.circ_matrix.sql

CREATE OR REPLACE FUNCTION actor.calculate_system_penalties( match_user INT, context_org INT ) RETURNS SETOF actor.usr_standing_penalty AS $func$
DECLARE
    user_object         actor.usr%ROWTYPE;
    new_sp_row          actor.usr_standing_penalty%ROWTYPE;
    existing_sp_row     actor.usr_standing_penalty%ROWTYPE;
    collections_fines   permission.grp_penalty_threshold%ROWTYPE;
    max_fines           permission.grp_penalty_threshold%ROWTYPE;
    max_overdue         permission.grp_penalty_threshold%ROWTYPE;
    max_items_out       permission.grp_penalty_threshold%ROWTYPE;
    max_lost            permission.grp_penalty_threshold%ROWTYPE;
    max_longoverdue     permission.grp_penalty_threshold%ROWTYPE;
    tmp_grp             INT;
    items_overdue       INT;
    items_out           INT;
    items_lost          INT;
    items_longoverdue   INT;
    context_org_list    INT[];
    current_fines        NUMERIC(8,2) := 0.0;
    tmp_fines            NUMERIC(8,2);
    tmp_groc            RECORD;
    tmp_circ            RECORD;
    tmp_org             actor.org_unit%ROWTYPE;
    tmp_penalty         config.standing_penalty%ROWTYPE;
    tmp_depth           INTEGER;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Max fines
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a high fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 1 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 1;

        SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 1;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max overdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many overdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_overdue FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 2 AND org_unit = tmp_org.id;

            IF max_overdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_overdue.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_overdue.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_overdue.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 2;

        SELECT  INTO items_overdue COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_overdue.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND circ.due_date < NOW()
            AND (circ.stop_fines = 'MAXFINES' OR circ.stop_fines IS NULL);

        IF items_overdue >= max_overdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_overdue.org_unit;
            new_sp_row.standing_penalty := 2;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max out
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many checked out items
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_items_out FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 3 AND org_unit = tmp_org.id;

            IF max_items_out.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_items_out.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;


    -- Fail if the user has too many items checked out
    IF max_items_out.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_items_out.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 3;

        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_items_out.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
                AND circ.checkin_time IS NULL
                AND (circ.stop_fines IN (
                    SELECT 'MAXFINES'::TEXT
                    UNION ALL
                    SELECT 'LONGOVERDUE'::TEXT
                    UNION ALL
                    SELECT 'LOST'::TEXT
                    WHERE 'true' ILIKE
                    (
                        SELECT CASE
                            WHEN (SELECT value FROM actor.org_unit_ancestor_setting('circ.tally_lost', circ.circ_lib)) ILIKE 'true' THEN 'true'
                            ELSE 'false'
                        END
                    )
                    UNION ALL
                    SELECT 'CLAIMSRETURNED'::TEXT
                    WHERE 'false' ILIKE
                    (
                        SELECT CASE
                            WHEN (SELECT value FROM actor.org_unit_ancestor_setting('circ.do_not_tally_claims_returned', circ.circ_lib)) ILIKE 'true' THEN 'true'
                            ELSE 'false'
                        END
                    )
                    ) OR circ.stop_fines IS NULL)
                AND xact_finish IS NULL;

           IF items_out >= max_items_out.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_items_out.org_unit;
            new_sp_row.standing_penalty := 3;
            RETURN NEXT new_sp_row;
           END IF;
    END IF;

    -- Start over for max lost
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many lost items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_lost FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 5 AND org_unit = tmp_org.id;

            IF max_lost.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_lost.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_lost.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
            FROM  actor.usr_standing_penalty
            WHERE usr = match_user
                AND org_unit = max_lost.org_unit
                AND (stop_date IS NULL or stop_date > NOW())
                AND standing_penalty = 5;

        SELECT  INTO items_lost COUNT(*)
        FROM  action.circulation circ
            JOIN  actor.org_unit_full_path( max_lost.org_unit ) fp ON (circ.circ_lib = fp.id)
        WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines = 'LOST')
            AND xact_finish IS NULL;

        IF items_lost >= max_lost.threshold::INT AND 0 < max_lost.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_lost.org_unit;
            new_sp_row.standing_penalty := 5;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max longoverdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many longoverdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_longoverdue 
                FROM permission.grp_penalty_threshold 
                WHERE grp = tmp_grp AND 
                    penalty = 35 AND 
                    org_unit = tmp_org.id;

            IF max_longoverdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp 
                    FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_longoverdue.threshold IS NOT NULL 
                OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_longoverdue.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
            FROM  actor.usr_standing_penalty
            WHERE usr = match_user
                AND org_unit = max_longoverdue.org_unit
                AND (stop_date IS NULL or stop_date > NOW())
                AND standing_penalty = 35;

        SELECT INTO items_longoverdue COUNT(*)
        FROM action.circulation circ
            JOIN actor.org_unit_full_path( max_longoverdue.org_unit ) fp 
                ON (circ.circ_lib = fp.id)
        WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines = 'LONGOVERDUE')
            AND xact_finish IS NULL;

        IF items_longoverdue >= max_longoverdue.threshold::INT 
                AND 0 < max_longoverdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_longoverdue.org_unit;
            new_sp_row.standing_penalty := 35;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;


    -- Start over for collections warning
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a collections-level fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 4 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 4;

        SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 4;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for in collections
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Remove the in-collections penalty if the user has paid down enough
    -- This penalty is different, because this code is not responsible for creating 
    -- new in-collections penalties, only for removing them
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 30 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        -- first, see if the user had paid down to the threshold
        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines IS NULL OR current_fines <= max_fines.threshold THEN
            -- patron has paid down enough

            SELECT INTO tmp_penalty * FROM config.standing_penalty WHERE id = 30;

            IF tmp_penalty.org_depth IS NOT NULL THEN

                -- since this code is not responsible for applying the penalty, it can't 
                -- guarantee the current context org will match the org at which the penalty 
                --- was applied.  search up the org tree until we hit the configured penalty depth
                SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;
                SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;

                WHILE tmp_depth >= tmp_penalty.org_depth LOOP

                    RETURN QUERY
                        SELECT  *
                          FROM  actor.usr_standing_penalty
                          WHERE usr = match_user
                                AND org_unit = tmp_org.id
                                AND (stop_date IS NULL or stop_date > NOW())
                                AND standing_penalty = 30;

                    IF tmp_org.parent_ou IS NULL THEN
                        EXIT;
                    END IF;

                    SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;
                    SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;
                END LOOP;

            ELSE

                -- no penalty depth is defined, look for exact matches

                RETURN QUERY
                    SELECT  *
                      FROM  actor.usr_standing_penalty
                      WHERE usr = match_user
                            AND org_unit = max_fines.org_unit
                            AND (stop_date IS NULL or stop_date > NOW())
                            AND standing_penalty = 30;
            END IF;
    
        END IF;

    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


-- from 110.hold_matrix.sql

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object     asset.call_number%ROWTYPE;
    item_status_object  config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
    hold_penalty TEXT;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( pickup_ou );

    result.success := TRUE;

    -- The HOLD penalty block only applies to new holds.
    -- The CAPTURE penalty block applies to existing holds.
    hold_penalty := 'HOLD';
    IF retargetting THEN
        hold_penalty := 'CAPTURE';
    END IF;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO item_status_object * FROM config.copy_status WHERE id = item_object.status;
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_object.holdable IS FALSE THEN
        result.fail_part := 'item.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_status_object.holdable IS FALSE THEN
        result.fail_part := 'status.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_location_object.holdable IS FALSE THEN
        result.fail_part := 'location.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;
 
    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE '%' || hold_penalty || '%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP
    
            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_cn_object.owning_lib);
        ELSE
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_object.circ_lib);
        END IF;
        IF use_active_date = 'true' THEN
            age_protect_date := COALESCE(item_object.active_date, NOW());
        ELSE
            age_protect_date := item_object.create_date;
        END IF;
        IF age_protect_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


-- from 300.schema.staged_search.sql

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL,
    deleted_search  BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );

    ELSIF param_search_ou < 0 THEN
        SELECT ARRAY_AGG(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP
            SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT ARRAY_AGG(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
        SELECT array_agg(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors(param_pref_ou);
        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        IF NOT deleted_search THEN

            PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
                deleted_count := deleted_count + 1;
                CONTINUE;
            END IF;

            PERFORM 1
              FROM  biblio.record_entry b
                    JOIN config.bib_source s ON (b.source = s.id)
              WHERE s.transcendant
                    AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

            IF FOUND THEN
                -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;

                tmp_int := 1;
                IF metarecord THEN
                    SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
                END IF;

                IF tmp_int = 1 THEN
                    current_res.record = core_result.records[1];
                ELSE
                    current_res.record = NULL;
                END IF;

                RETURN NEXT current_res;

                CONTINUE;
            END IF;

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                    JOIN asset.uri uri ON (map.uri = uri.id)
              WHERE NOT cn.deleted
                    AND cn.label = '##URI##'
                    AND uri.active
                    AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
              LIMIT 1;

            IF FOUND THEN
                -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;

                tmp_int := 1;
                IF metarecord THEN
                    SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
                END IF;

                IF tmp_int = 1 THEN
                    current_res.record = core_result.records[1];
                ELSE
                    current_res.record = NULL;
                END IF;

                RETURN NEXT current_res;

                CONTINUE;
            END IF;

            IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF staff IS NULL OR NOT staff THEN

                PERFORM 1
                  FROM  asset.opac_visible_copies
                  WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                      WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            ELSE

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        PERFORM 1
                          FROM  asset.call_number cn
                                JOIN asset.copy cp ON (cp.call_number = cn.id)
                          WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                AND NOT cp.deleted
                          LIMIT 1;

                        IF FOUND THEN
                            -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                            excluded_count := excluded_count + 1;
                            CONTINUE;
                        END IF;
                    END IF;

                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;


-- from 990.schema.unapi.sql

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT)
RETURNS anyarray AS $$
    SELECT ARRAY_AGG(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2;
$$ LANGUAGE SQL STABLE;


-- from 999.functions.global.sql

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
			' tag="856"' ||
			' ind1="' || FIRST(ind1) || '"'  ||
			' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

	-- Find and move metarecords to the target record
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
			AND owning_lib = source_cn.owning_lib
			AND record = target_record
			AND NOT deleted;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial subscriptions targeting the source record ...
	FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.subscription
		  SET	record_entry = target_record
		  WHERE	id = ser_sub.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find booking resource types targeting the source record ...
	FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	booking.resource_type
		  SET	record = target_record
		  WHERE	id = booking.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq lineitems targeting the source record ...
	FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.lineitem
		  SET	eg_bib_id = target_record
		  WHERE	id = acq_lineitem.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq user purchase requests targeting the source record ...
	FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.user_request
		  SET	eg_bib = target_record
		  WHERE	id = acq_request.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find parts attached to the source ...
	FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

		SELECT	INTO target_part *
		  FROM	biblio.monograph_part
		  WHERE	label = source_part.label
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copy-part maps to that, and ...
			UPDATE	asset.copy_part_map
			  SET	part = target_part.id
			  WHERE	part = source_part.id;

			-- ... move P holds to the move-target part
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_part.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the part to the target record
			UPDATE	biblio.monograph_part
			  SET	record = target_record
			  WHERE	id = source_part.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find multi_home items attached to the source ...
	FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	biblio.peer_bib_copy_map
		  SET	peer_record = target_record
		  WHERE	id = multi_home.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- And delete mappings where the item's home bib was merged with the peer bib
	DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
		SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
		FROM asset.copy WHERE id = target_copy
	);

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

-- from reporter-schema.sql

CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT	r.id,
	s.metarecord,
	r.fingerprint,
	r.quality,
	r.tcn_source,
	r.tcn_value,
	title.value AS title,
	uniform_title.value AS uniform_title,
	author.value AS author,
	publisher.value AS publisher,
	SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
	series_title.value AS series_title,
	series_statement.value AS series_statement,
	summary.value AS summary,
	ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
	ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
	ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM	biblio.record_entry r
	JOIN metabib.metarecord_source_map s ON (s.source = r.id)
	LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
	LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
	LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
	LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    STRING_AGG(DISTINCT publisher.value, ', ') AS publisher,
    STRING_AGG(DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$), ', ') AS pubdate,
    CASE WHEN ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') )
    END AS isbn,
    CASE WHEN ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') )
    END AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

COMMIT;

-- Not running changes from example.reporter-extension.sql since these are
-- not installed by default, but including a helpful note.

\qecho 'There were also changes in example.reporter-extension.sql'
\qecho 'Please run that script again if you use it in your system'
\qecho 'to apply new changes.'


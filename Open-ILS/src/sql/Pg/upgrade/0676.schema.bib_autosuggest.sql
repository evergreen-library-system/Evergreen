BEGIN;

SELECT evergreen.upgrade_deps_block_check('0676', :eg_version);

INSERT INTO config.global_flag (name, label, enabled, value) VALUES (
    'opac.use_autosuggest',
    'OPAC: Show auto-completing suggestions dialog under basic search box (put ''opac_visible'' into the value field to limit suggestions to OPAC-visible items, or blank the field for a possible performance improvement)',
    TRUE,
    'opac_visible'
);

CREATE TABLE metabib.browse_entry (
    id BIGSERIAL PRIMARY KEY,
    value TEXT unique,
    index_vector tsvector
);
CREATE INDEX metabib_browse_entry_index_vector_idx ON metabib.browse_entry USING GIST (index_vector);
CREATE TRIGGER metabib_browse_entry_fti_trigger
    BEFORE INSERT OR UPDATE ON metabib.browse_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');


CREATE TABLE metabib.browse_entry_def_map (
    id BIGSERIAL PRIMARY KEY,
    entry BIGINT REFERENCES metabib.browse_entry (id),
    def INT REFERENCES config.metabib_field (id),
    source BIGINT REFERENCES biblio.record_entry (id)
);

ALTER TABLE config.metabib_field ADD COLUMN browse_field BOOLEAN DEFAULT TRUE NOT NULL;
ALTER TABLE config.metabib_field ADD COLUMN browse_xpath TEXT;

ALTER TABLE config.metabib_class ADD COLUMN bouyant BOOLEAN DEFAULT FALSE NOT NULL;
ALTER TABLE config.metabib_class ADD COLUMN restrict BOOLEAN DEFAULT FALSE NOT NULL;
ALTER TABLE config.metabib_field ADD COLUMN restrict BOOLEAN DEFAULT FALSE NOT NULL;

-- one good exception to default true:
UPDATE config.metabib_field
    SET browse_field = FALSE
    WHERE (field_class = 'keyword' AND name = 'keyword') OR
        (field_class = 'subject' AND name = 'complete');

-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
-- We're only touching it here to add a DELETE statement to the IF NEW.deleted
-- block.

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
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM metabib.record_attr WHERE id = NEW.id; -- Kill the attrs hash, useless on deleted records
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
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
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

CREATE OR REPLACE FUNCTION metabib.browse_normalize(facet_text TEXT, mapped_field INT) RETURNS TEXT AS $$
DECLARE
    normalizer  RECORD;
BEGIN

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = mapped_field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( facet_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO facet_text;

    END LOOP;

    RETURN facet_text;
END;

$$ LANGUAGE PLPGSQL;

DROP FUNCTION biblio.extract_metabib_field_entry(bigint, text);
DROP FUNCTION biblio.extract_metabib_field_entry(bigint);

DROP TYPE metabib.field_entry_template;
CREATE TYPE metabib.field_entry_template AS (
        field_class     TEXT,
        field           INT,
        facet_field     BOOL,
        search_field    BOOL,
        browse_field   BOOL,
        source          BIGINT,
        value           TEXT
);


CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    browse_text TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            curr_text := ARRAY_TO_STRING(
                oils_xpath( '//text()',
                    REGEXP_REPLACE( -- This escapes all &s not followed by "amp;".  Data ise returned from oils_xpath (above) in UTF-8, not entity encoded
                        REGEXP_REPLACE( -- This escapes embeded <s
                            xml_node,
                            $re$(>[^<]+)(<)([^>]+<)$re$,
                            E'\\1&lt;\\3',
                            'g'
                        ),
                        '&(?!amp;)',
                        '&amp;',
                        'g'
                    )
                ),
                ' '
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));

                output_row.browse_field = TRUE;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
        END IF;

    END LOOP;

END;
$func$ LANGUAGE PLPGSQL;

-- default to a space joiner
CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( BIGINT ) RETURNS SETOF metabib.field_entry_template AS $func$
    SELECT * FROM biblio.extract_metabib_field_entry($1, ' ');
    $func$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        FOR fclass IN SELECT * FROM config.metabib_class LOOP
            -- RAISE NOTICE 'Emptying out %', fclass.name;
            EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
        END LOOP;
        DELETE FROM metabib.facet_entry WHERE source = bib_id;
        DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field THEN
            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = ind_data.value;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES
                    (metabib.browse_normalize(ind_data.value, ind_data.field));
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- This mimics a specific part of QueryParser, turning the first part of a
-- classed search (search_class) into a set of classes and possibly fields.
-- search_class might look like "author" or "title|proper" or "ti|uniform"
-- or "au" or "au|corporate|personal" or anything like that, where the first
-- element of the list you get by separating on the "|" character is either
-- a registered class (config.metabib_class) or an alias
-- (config.metabib_search_alias), and the rest of any such elements are
-- fields (config.metabib_field).
CREATE OR REPLACE
    FUNCTION metabib.search_class_to_registered_components(search_class TEXT)
    RETURNS SETOF RECORD AS $func$
DECLARE
    search_parts        TEXT[];
    field_name          TEXT;
    search_part_count   INTEGER;
    rec                 RECORD;
    registered_class    config.metabib_class%ROWTYPE;
    registered_alias    config.metabib_search_alias%ROWTYPE;
    registered_field    config.metabib_field%ROWTYPE;
BEGIN
    search_parts := REGEXP_SPLIT_TO_ARRAY(search_class, E'\\|');

    search_part_count := ARRAY_LENGTH(search_parts, 1);
    IF search_part_count = 0 THEN
        RETURN;
    ELSE
        SELECT INTO registered_class
            * FROM config.metabib_class WHERE name = search_parts[1];
        IF FOUND THEN
            IF search_part_count < 2 THEN   -- all fields
                rec := (registered_class.name, NULL::INTEGER);
                RETURN NEXT rec;
                RETURN; -- done
            END IF;
            FOR field_name IN SELECT *
                FROM UNNEST(search_parts[2:search_part_count]) LOOP
                SELECT INTO registered_field
                    * FROM config.metabib_field
                    WHERE name = field_name AND
                        field_class = registered_class.name;
                IF FOUND THEN
                    rec := (registered_class.name, registered_field.id);
                    RETURN NEXT rec;
                END IF;
            END LOOP;
        ELSE
            -- maybe we have an alias?
            SELECT INTO registered_alias
                * FROM config.metabib_search_alias WHERE alias=search_parts[1];
            IF NOT FOUND THEN
                RETURN;
            ELSE
                IF search_part_count < 2 THEN   -- return w/e the alias says
                    rec := (
                        registered_alias.field_class, registered_alias.field
                    );
                    RETURN NEXT rec;
                    RETURN; -- done
                ELSE
                    FOR field_name IN SELECT *
                        FROM UNNEST(search_parts[2:search_part_count]) LOOP
                        SELECT INTO registered_field
                            * FROM config.metabib_field
                            WHERE name = field_name AND
                                field_class = registered_alias.field_class;
                        IF FOUND THEN
                            rec := (
                                registered_alias.field_class,
                                registered_field.id
                            );
                            RETURN NEXT rec;
                        END IF;
                    END LOOP;
                END IF;
            END IF;
        END IF;
    END IF;
END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE
    FUNCTION metabib.suggest_browse_entries(
        query_text      TEXT,   -- 'foo' or 'foo & ba:*',ready for to_tsquery()
        search_class    TEXT,   -- 'alias' or 'class' or 'class|field..', etc
        headline_opts   TEXT,   -- markup options for ts_headline()
        visibility_org  INTEGER,-- null if you don't want opac visibility test
        query_limit     INTEGER,-- use in LIMIT clause of interal query
        normalization   INTEGER -- argument to TS_RANK_CD()
    ) RETURNS TABLE (
        value                   TEXT,   -- plain
        field                   INTEGER,
        bouyant_and_class_match BOOL,
        field_match             BOOL,
        field_weight            INTEGER,
        rank                    REAL,
        bouyant                 BOOL,
        match                   TEXT    -- marked up
    ) AS $func$
DECLARE
    query                   TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    query := TO_TSQUERY('keyword', query_text);

    IF visibility_org IS NOT NULL THEN
        opac_visibility_join := '
    JOIN asset.opac_visible_copies aovc ON (
        aovc.record = mbedm.source AND
        aovc.circ_lib IN (SELECT id FROM actor.org_unit_descendants($4))
    )';
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE 'SELECT *, TS_HEADLINE(value, $1, $3) FROM (SELECT DISTINCT
        mbe.value,
        cmf.id,
        cmc.bouyant AND _registered.field_class IS NOT NULL,
        _registered.field = cmf.id,
        cmf.weight,
        TS_RANK_CD(mbe.index_vector, $1, $6),
        cmc.bouyant
    FROM metabib.browse_entry_def_map mbedm
    JOIN metabib.browse_entry mbe ON (mbe.id = mbedm.entry)
    JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
    JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
    '  || search_class_join || opac_visibility_join ||
    ' WHERE $1 @@ mbe.index_vector
    ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
    LIMIT $5) x
    ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
    '   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization
        ;

    -- sort order:
    --  bouyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  bouyancy
    --  value itself

END;
$func$ LANGUAGE PLPGSQL;

-- The advantage of this over the stock regexp_split_to_array() is that it
-- won't degrade unicode strings.
CREATE OR REPLACE FUNCTION evergreen.regexp_split_to_array(TEXT, TEXT)
RETURNS TEXT[] AS $$
    return encode_array_literal([split $_[1], $_[0]]);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;


-- Adds some logic for browse_entry to split on non-word chars for index_vector, post-normalize
CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
BEGIN

    value := NEW.value;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;

        NEW.value := value;
    END IF;

    IF NEW.index_vector = ''::tsvector THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN
        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
    END IF;

    NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, value);

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

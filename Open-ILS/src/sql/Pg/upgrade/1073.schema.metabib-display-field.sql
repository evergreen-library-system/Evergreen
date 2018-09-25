
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1073', :eg_version);

ALTER TABLE config.metabib_field 
    ADD COLUMN display_xpath TEXT, 
    ADD COLUMN display_field BOOL NOT NULL DEFAULT FALSE;

CREATE TABLE config.display_field_map (
    name    TEXT   PRIMARY KEY,
    field   INTEGER REFERENCES config.metabib_field (id),
    multi   BOOLEAN DEFAULT FALSE
);

CREATE TABLE metabib.display_entry (
    id      BIGSERIAL  PRIMARY KEY,
    source  BIGINT     NOT NULL REFERENCES biblio.record_entry (id),
    field   INT        NOT NULL REFERENCES config.metabib_field (id),
    value   TEXT       NOT NULL
);

CREATE INDEX metabib_display_entry_field_idx ON metabib.display_entry (field);
CREATE INDEX metabib_display_entry_source_idx ON metabib.display_entry (source);

-- one row per display entry fleshed with field info
CREATE VIEW metabib.flat_display_entry AS
    SELECT
        mde.source,
        cdfm.name,
        cdfm.multi,
        cmf.label,
        cmf.id AS field,
        mde.value
    FROM metabib.display_entry mde
    JOIN config.metabib_field cmf ON (cmf.id = mde.field)
    JOIN config.display_field_map cdfm ON (cdfm.field = mde.field)
;

-- like flat_display_entry except values are compressed 
-- into one row per display_field_map and JSON-ified.
CREATE VIEW metabib.compressed_display_entry AS
    SELECT 
        source,
        name,
        multi,
        label,
        field,
        CASE WHEN multi THEN
            TO_JSON(ARRAY_AGG(value))
        ELSE
            TO_JSON(MIN(value))
        END AS value
    FROM metabib.flat_display_entry
    GROUP BY 1, 2, 3, 4, 5
;

-- TODO: expand to encompass all well-known fields
CREATE VIEW metabib.wide_display_entry AS
    SELECT 
        bre.id AS source,
        COALESCE(mcde_title.value, 'null') AS title,
        COALESCE(mcde_author.value, 'null') AS author,
        COALESCE(mcde_subject.value, 'null') AS subject,
        COALESCE(mcde_creators.value, 'null') AS creators,
        COALESCE(mcde_isbn.value, 'null') AS isbn
    -- ensure one row per bre regardless of any display fields
    FROM biblio.record_entry bre 
    LEFT JOIN metabib.compressed_display_entry mcde_title 
        ON (bre.id = mcde_title.source AND mcde_title.name = 'title')
    LEFT JOIN metabib.compressed_display_entry mcde_author 
        ON (bre.id = mcde_author.source AND mcde_author.name = 'author')
    LEFT JOIN metabib.compressed_display_entry mcde_subject 
        ON (bre.id = mcde_subject.source AND mcde_subject.name = 'subject')
    LEFT JOIN metabib.compressed_display_entry mcde_creators 
        ON (bre.id = mcde_creators.source AND mcde_creators.name = 'creators')
    LEFT JOIN metabib.compressed_display_entry mcde_isbn 
        ON (bre.id = mcde_isbn.source AND mcde_isbn.name = 'isbn')
;


CREATE OR REPLACE FUNCTION metabib.display_field_normalize_trigger () 
    RETURNS TRIGGER AS $$
DECLARE
    normalizer  RECORD;
    display_field_text  TEXT;
BEGIN
    display_field_text := NEW.value;

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = NEW.field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( display_field_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(
                            normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO display_field_text;

    END LOOP;

    NEW.value = display_field_text;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER display_field_normalize_tgr
	BEFORE UPDATE OR INSERT ON metabib.display_entry
	FOR EACH ROW EXECUTE PROCEDURE metabib.display_field_normalize_trigger();

CREATE OR REPLACE FUNCTION evergreen.display_field_force_nfc() 
    RETURNS TRIGGER AS $$
BEGIN
    NEW.value := force_unicode_normal_form(NEW.value,'NFC');
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER display_field_force_nfc_tgr
	BEFORE UPDATE OR INSERT ON metabib.display_entry
	FOR EACH ROW EXECUTE PROCEDURE evergreen.display_field_force_nfc();

ALTER TYPE metabib.field_entry_template ADD ATTRIBUTE display_field BOOL;

DROP FUNCTION metabib.reingest_metabib_field_entries(BIGINT, BOOL, BOOL, BOOL);
DROP FUNCTION biblio.extract_metabib_field_entry(BIGINT);
DROP FUNCTION biblio.extract_metabib_field_entry(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry (
    rid BIGINT,
    default_joiner TEXT,
    field_types TEXT[],
    only_fields INT[]
) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    display_text TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
    process_idx BOOL;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.display_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field WHERE id = ANY (only_fields) ORDER BY format LOOP

        process_idx := FALSE;
        IF idx.display_field AND 'display' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.browse_field AND 'browse' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.search_field AND 'search' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.facet_field AND 'facet' = ANY (field_types) THEN process_idx = TRUE; END IF;
        CONTINUE WHEN process_idx = FALSE;

        joiner := COALESCE(idx.joiner, default_joiner);

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

            -- XXX much of this should be moved into oils_xpath_string...
            curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                    REGEXP_REPLACE( xml_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                joiner
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

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.naco_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                -- Returning browse rows with search_field = true for search+browse
                -- configs allows us to retain granularity of being able to search
                -- browse fields with "starts with" type operators (for example, for
                -- titles of songs in music albums)
                IF idx.search_field THEN
                    output_row.search_field = TRUE;
                END IF;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
                output_row.search_field = FALSE;
                output_row.sort_value := NULL;
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

            -- insert raw node text for display
            IF idx.display_field THEN

                IF idx.display_xpath IS NOT NULL AND idx.display_xpath <> '' THEN
                    display_text := oils_xpath_string( idx.display_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    display_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(display_text, E'\\s+', ' ', 'g'));

                output_row.display_field = TRUE;
                RETURN NEXT output_row;
                output_row.display_field = FALSE;
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
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;

$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( 
    bib_id BIGINT,
    skip_facet BOOL DEFAULT FALSE, 
    skip_display BOOL DEFAULT FALSE,
    skip_browse BOOL DEFAULT FALSE, 
    skip_search BOOL DEFAULT FALSE,
    only_fields INT[] DEFAULT '{}'::INT[]
) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_display    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
    field_list      INT[] := only_fields;
    field_types     TEXT[] := '{}'::TEXT[];
BEGIN

    IF field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO field_list FROM config.metabib_field;
    END IF;

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_display, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_display_indexing' AND enabled)) INTO b_skip_display;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    IF NOT b_skip_facet THEN field_types := field_types || '{facet}'; END IF;
    IF NOT b_skip_display THEN field_types := field_types || '{display}'; END IF;
    IF NOT b_skip_browse THEN field_types := field_types || '{browse}'; END IF;
    IF NOT b_skip_search THEN field_types := field_types || '{search}'; END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_display THEN
            DELETE FROM metabib.display_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id, ' ', field_types, field_list ) LOOP

	-- don't store what has been normalized away
        CONTINUE WHEN ind_data.value IS NULL;

        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.display_field AND NOT b_skip_display THEN
            INSERT INTO metabib.display_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;


        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            CONTINUE WHEN ind_data.sort_value IS NULL;

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            SELECT INTO mbe_row * FROM metabib.browse_entry
                WHERE value = value_prepped AND sort_value = ind_data.sort_value;

            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value );

                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            -- Avoid inserting duplicate rows
            EXECUTE 'SELECT 1 FROM metabib.' || ind_data.field_class ||
                '_field_entry WHERE field = $1 AND source = $2 AND value = $3'
                INTO mbe_id USING ind_data.field, ind_data.source, ind_data.value;
                -- RAISE NOTICE 'Search for an already matching row returned %', mbe_id;
            IF mbe_id IS NULL THEN
                EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
            END IF;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    tmp_bool BOOL;
BEGIN

    IF NEW.deleted THEN -- If this bib is deleted

        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;

        tmp_bool := FOUND; -- Just in case this is changed by some other statement

        PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint, TRUE, tmp_bool );

        IF NOT tmp_bool THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.record_attr_vector_list WHERE source = NEW.id;
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
            PERFORM metabib.reingest_record_attributes(NEW.id, NULL, NEW.marc, TG_OP = 'INSERT' OR OLD.deleted);
        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
    IF NOT FOUND THEN PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor ); END IF;

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

COMMIT;


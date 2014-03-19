BEGIN;

SELECT evergreen.upgrade_deps_block_check('0874', :eg_version);

DROP FUNCTION IF EXISTS evergreen.oils_xpath( TEXT, TEXT, ANYARRAY);
DROP FUNCTION IF EXISTS public.oils_xpath(TEXT, TEXT, ANYARRAY);
DROP FUNCTION IF EXISTS public.oils_xpath(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.oils_xslt_process(TEXT, TEXT);

CREATE OR REPLACE FUNCTION evergreen.xml_famous5_to_text( TEXT ) RETURNS TEXT AS $f$
 SELECT REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE( $1, '&lt;', '<'),
                        '&gt;',
                        '>'
                    ),
                    '&apos;',
                    $$'$$
                ), -- ' ... vim
                '&quot;',
                '"'
            ),
            '&amp;',
            '&'
        );
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.oils_xpath ( TEXT, TEXT, TEXT[] ) RETURNS TEXT[] AS $f$
    SELECT  ARRAY_AGG(
                CASE WHEN strpos(x,'<') = 1 THEN -- It's an element node
                    x
                ELSE -- it's text-ish
                    evergreen.xml_famous5_to_text(x)
                END
            )
      FROM  UNNEST(XPATH( $1, $2::XML, $3 )::TEXT[]) x;
$f$ LANGUAGE SQL IMMUTABLE;

-- Trust me, it's just simpler to duplicate these...
CREATE OR REPLACE FUNCTION evergreen.oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS $f$
    SELECT  ARRAY_AGG(
                CASE WHEN strpos(x,'<') = 1 THEN -- It's an element node
                    x
                ELSE -- it's text-ish
                    evergreen.xml_famous5_to_text(x)
                END
            )
      FROM  UNNEST(XPATH( $1, $2::XML)::TEXT[]) x;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $func$
  use strict;

  use XML::LibXSLT;
  use XML::LibXML;

  my $doc = shift;
  my $xslt = shift;

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new();

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  my $xslt_parser = $_SHARED{'_xslt_process'}{parsers}{xslt} || XML::LibXSLT->new();

  # Cache the XSLT processor, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xslt} = $xslt_parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xslt});

  my $stylesheet = $_SHARED{'_xslt_process'}{stylesheets}{$xslt} ||
    $xslt_parser->parse_stylesheet( $parser->parse_string($xslt) );

  $_SHARED{'_xslt_process'}{stylesheets}{$xslt} = $stylesheet
    unless ($_SHARED{'_xslt_process'}{stylesheets}{$xslt});

  return $stylesheet->output_string(
    $stylesheet->transform(
      $parser->parse_string($doc)
    )
  );

$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    joiner_text     TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT; 
BEGIN

    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN ( SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    res.record := auth_id;

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP

        res.atag := acsaf.id;
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        joiner_text := COALESCE(acsaf.joiner, ' ');

        FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)::TEXT[]) LOOP

            heading_text := COALESCE(
                oils_xpath_string('./*[contains("'||acsaf.display_sf_list||'",@code)]', tmp_xml, joiner_text),
                ''
            );

            IF nfi_used IS NOT NULL THEN

                sort_text := SUBSTRING(
                    heading_text FROM
                    COALESCE(
                        NULLIF(
                            REGEXP_REPLACE(
                                oils_xpath_string('./@ind'||nfi_used, tmp_xml::TEXT),
                                $$\D+$$,
                                '',
                                'g'
                            ),
                            ''
                        )::INT,
                        0
                    ) + 1
                );

            ELSE
                sort_text := heading_text;
            END IF;

            IF heading_text IS NOT NULL AND heading_text <> '' THEN
                res.value := heading_text;
                res.sort_value := public.naco_normalize(sort_text);
                res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                RETURN NEXT res;
            END IF;

        END LOOP;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION url_verify.extract_urls ( session_id INT, item_id INT ) RETURNS INT AS $$
DECLARE
    last_seen_tag TEXT;
    current_tag TEXT;
    current_sf TEXT;
    current_url TEXT;
    current_ord INT;
    current_url_pos INT;
    current_selector url_verify.url_selector%ROWTYPE;
BEGIN
    current_ord := 1;

    FOR current_selector IN SELECT * FROM url_verify.url_selector s WHERE s.session = session_id LOOP
        current_url_pos := 1;
        LOOP
            SELECT  (oils_xpath(current_selector.xpath || '/text()', b.marc))[current_url_pos] INTO current_url
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            EXIT WHEN current_url IS NULL;

            SELECT  (oils_xpath(current_selector.xpath || '/../@tag', b.marc))[current_url_pos] INTO current_tag
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            IF current_tag IS NULL THEN
                current_tag := last_seen_tag;
            ELSE
                last_seen_tag := current_tag;
            END IF;

            SELECT  (oils_xpath(current_selector.xpath || '/@code', b.marc))[current_url_pos] INTO current_sf
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            INSERT INTO url_verify.url (session, item, url_selector, tag, subfield, ord, full_url)
              VALUES ( session_id, item_id, current_selector.id, current_tag, current_sf, current_ord, current_url);

            current_url_pos := current_url_pos + 1;
            current_ord := current_ord + 1;
        END LOOP;
    END LOOP;

    RETURN current_ord - 1;
END;
$$ LANGUAGE PLPGSQL;

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
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

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

CREATE OR REPLACE FUNCTION metabib.reingest_record_attributes (rid BIGINT, pattr_list TEXT[] DEFAULT NULL, prmarc TEXT DEFAULT NULL, rdeleted BOOL DEFAULT TRUE) RETURNS VOID AS $func$
DECLARE
    transformed_xml TEXT;
    rmarc           TEXT := prmarc;
    tmp_val         TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_vector     INT[] := '{}'::INT[];
    attr_vector_tmp INT[];
    attr_list       TEXT[] := pattr_list;
    attr_value      TEXT[];
    norm_attr_value TEXT[];
    tmp_xml         TEXT;
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition;
    END IF;

    IF rmarc IS NULL THEN
        SELECT marc INTO rmarc FROM biblio.record_entry WHERE id = rid;
    END IF;

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE NOT composite AND name = ANY( attr_list ) ORDER BY format LOOP

        attr_value := '{}'::TEXT[];
        norm_attr_value := '{}'::TEXT[];
        attr_vector_tmp := '{}'::INT[];

        SELECT * INTO ccvm_row FROM config.coded_value_map c WHERE c.ctype = attr_def.name LIMIT 1; 

        -- tag+sf attrs only support SVF
        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY[ARRAY_TO_STRING(ARRAY_AGG(value), COALESCE(attr_def.joiner,' '))] INTO attr_value
              FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
              WHERE record = rid
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
            attr_value := vandelay.marc21_extract_fixed_field_list(rmarc, attr_def.fixed_field);

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
        
            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(rmarc,xfrm.xslt);
                ELSE
                    transformed_xml := rmarc;
                END IF;
    
                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            FOR tmp_xml IN SELECT oils_xpath(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml,
                                COALESCE(attr_def.joiner,' '),
                                ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                            );
                IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                    attr_value := attr_value || tmp_val;
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END LOOP;

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  ARRAY_AGG(m.value) INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(rmarc) v
                    LEFT JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf AND (m.value IS NOT NULL AND BTRIM(m.value) <> '')
                    AND ( ccvm_row.id IS NULL OR ( ccvm_row.id IS NOT NULL AND v.id IS NOT NULL) );

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        END IF;

                -- apply index normalizers to attr_value
        FOR tmp_val IN SELECT value FROM UNNEST(attr_value) x(value) LOOP
            FOR normalizer IN
                SELECT  n.func AS func,
                        n.param_count AS param_count,
                        m.params AS params
                  FROM  config.index_normalizer n
                        JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                  WHERE attr = attr_def.name
                  ORDER BY m.pos LOOP
                    EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    COALESCE( quote_literal( tmp_val ), 'NULL' ) ||
                        CASE
                            WHEN normalizer.param_count > 0
                                THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                ELSE ''
                            END ||
                    ')' INTO tmp_val;

            END LOOP;
            IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                norm_attr_value := norm_attr_value || tmp_val;
            END IF;
        END LOOP;
        
        IF attr_def.filter THEN
            -- Create unknown uncontrolled values and find the IDs of the values
            IF ccvm_row.id IS NULL THEN
                FOR tmp_val IN SELECT value FROM UNNEST(norm_attr_value) x(value) LOOP
                    IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                        BEGIN -- use subtransaction to isolate unique constraint violations
                            INSERT INTO metabib.uncontrolled_record_attr_value ( attr, value ) VALUES ( attr_def.name, tmp_val );
                        EXCEPTION WHEN unique_violation THEN END;
                    END IF;
                END LOOP;

                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM metabib.uncontrolled_record_attr_value WHERE attr = attr_def.name AND value = ANY( norm_attr_value );
            ELSE
                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM config.coded_value_map WHERE ctype = attr_def.name AND code = ANY( norm_attr_value );
            END IF;

            -- Add the new value to the vector
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

        IF attr_def.sorter AND norm_attr_value[1] IS NOT NULL THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
        END IF;

    END LOOP;

/* We may need to rewrite the vlist to contain
   the intersection of new values for requested
   attrs and old values for ignored attrs. To
   do this, we take the old attr vlist and
   subtract any values that are valid for the
   requested attrs, and then add back the new
   set of attr values. */

    IF ARRAY_LENGTH(pattr_list, 1) > 0 THEN 
        SELECT vlist INTO attr_vector_tmp FROM metabib.record_attr_vector_list WHERE source = rid;
        SELECT attr_vector_tmp - ARRAY_AGG(id::INT) INTO attr_vector_tmp FROM metabib.full_attr_id_map WHERE attr = ANY (pattr_list);
        attr_vector := attr_vector || attr_vector_tmp;
    END IF;

    -- On to composite attributes, now that the record attrs have been pulled.  Processed in name order, so later composite
    -- attributes can depend on earlier ones.
    PERFORM metabib.compile_composite_attr_cache_init();
    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE composite AND name = ANY( attr_list ) ORDER BY name LOOP

        FOR ccvm_row IN SELECT * FROM config.coded_value_map c WHERE c.ctype = attr_def.name ORDER BY value LOOP

            tmp_val := metabib.compile_composite_attr( ccvm_row.id );
            CONTINUE WHEN tmp_val IS NULL OR tmp_val = ''; -- nothing to do

            IF attr_def.filter THEN
                IF attr_vector @@ tmp_val::query_int THEN
                    attr_vector = attr_vector + intset(ccvm_row.id);
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END IF;

            IF attr_def.sorter THEN
                IF attr_vector @@ tmp_val THEN
                    DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
                    INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, ccvm_row.code);
                END IF;
            END IF;

        END LOOP;

    END LOOP;

    IF ARRAY_LENGTH(attr_vector, 1) > 0 THEN
        IF rdeleted THEN -- initial insert OR revivication
            DELETE FROM metabib.record_attr_vector_list WHERE source = rid;
            INSERT INTO metabib.record_attr_vector_list (source, vlist) VALUES (rid, attr_vector);
        ELSE
            UPDATE metabib.record_attr_vector_list SET vlist = attr_vector WHERE source = rid;
        END IF;
    END IF;

END;

$func$ LANGUAGE PLPGSQL;

COMMIT;

\qecho This script will now attempt a "quick fix" of browse_entry only.
\qecho If you have issues, a browse or full reingest is recommended.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.

UPDATE metabib.browse_entry SET value=evergreen.xml_famous5_to_text(value) WHERE value LIKE '%&%';
UPDATE metabib.browse_entry SET sort_value=evergreen.xml_famous5_to_text(sort_value) WHERE sort_value LIKE '%&%';

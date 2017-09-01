BEGIN;

SELECT evergreen.upgrade_deps_block_check('1069', :eg_version); --gmcharlt/kmlussier

-- subset of types listed in https://www.loc.gov/marc/authority/ad1xx3xx.html
-- for now, ignoring subdivisions
CREATE TYPE authority.heading_type AS ENUM (
    'personal_name',
    'corporate_name',
    'meeting_name',
    'uniform_title',
    'named_event',
    'chronological_term',
    'topical_term',
    'geographic_name',
    'genre_form_term',
    'medium_of_performance_term'
);

CREATE TYPE authority.variant_heading_type AS ENUM (
    'abbreviation',
    'acronym',
    'translation',
    'expansion',
    'other',
    'hidden'
);

CREATE TYPE authority.related_heading_type AS ENUM (
    'earlier',
    'later',
    'parent organization',
    'broader',
    'narrower',
    'equivalent',
    'other'
);

CREATE TYPE authority.heading_purpose AS ENUM (
    'main',
    'variant',
    'related'
);

CREATE TABLE authority.heading_field (
    id              SERIAL                      PRIMARY KEY,
    heading_type    authority.heading_type      NOT NULL,
    heading_purpose authority.heading_purpose   NOT NULL,
    label           TEXT                        NOT NULL,
    format          TEXT                        NOT NULL REFERENCES config.xml_transform (name) DEFAULT 'mads21',
    heading_xpath   TEXT                        NOT NULL,
    component_xpath TEXT                        NOT NULL,
    type_xpath      TEXT                        NULL, -- to extract related or variant type
    thesaurus_xpath TEXT                        NULL,
    thesaurus_override_xpath TEXT               NULL,
    joiner          TEXT                        NULL
);

CREATE TABLE authority.heading_field_norm_map (
        id      SERIAL  PRIMARY KEY,
        field   INT     NOT NULL REFERENCES authority.heading_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        params  TEXT,
        pos     INT     NOT NULL DEFAULT 0
);

INSERT INTO authority.heading_field(heading_type, heading_purpose, label, heading_xpath, component_xpath, type_xpath, thesaurus_xpath, thesaurus_override_xpath) VALUES
 ( 'topical_term', 'main',    'Main Topical Term',    '/mads21:mads/mads21:authority', '//mads21:topic', NULL, '/mads21:mads/mads21:authority/mads21:topic[1]/@authority', NULL )
,( 'topical_term', 'variant', 'Variant Topical Term', '/mads21:mads/mads21:variant',   '//mads21:topic', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:topic[1]/@authority', '//mads21:topic[1]/@authority')
,( 'topical_term', 'related', 'Related Topical Term', '/mads21:mads/mads21:related',   '//mads21:topic', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:topic[1]/@authority', '//mads21:topic[1]/@authority')
,( 'personal_name', 'main', 'Main Personal Name',     '/mads21:mads/mads21:authority', '//mads21:name[@type="personal"]', NULL, NULL, NULL )
,( 'personal_name', 'variant', 'Variant Personal Name',     '/mads21:mads/mads21:variant', '//mads21:name[@type="personal"]', NULL, NULL, NULL )
,( 'personal_name', 'related', 'Related Personal Name',     '/mads21:mads/mads21:related', '//mads21:name[@type="personal"]', '/mads21:related/@type', NULL, NULL )
,( 'corporate_name', 'main', 'Main Corporate name',     '/mads21:mads/mads21:authority', '//mads21:name[@type="corporate"]', NULL, NULL, NULL )
,( 'corporate_name', 'variant', 'Variant Corporate Name',     '/mads21:mads/mads21:variant', '//mads21:name[@type="corporate"]', NULL, NULL, NULL )
,( 'corporate_name', 'related', 'Related Corporate Name',     '/mads21:mads/mads21:related', '//mads21:name[@type="corporate"]', '/mads21:related/@type', NULL, NULL )
,( 'meeting_name', 'main', 'Main Meeting name',     '/mads21:mads/mads21:authority', '//mads21:name[@type="conference"]', NULL, NULL, NULL )
,( 'meeting_name', 'variant', 'Variant Meeting Name',     '/mads21:mads/mads21:variant', '//mads21:name[@type="conference"]', NULL, NULL, NULL )
,( 'meeting_name', 'related', 'Related Meeting Name',     '/mads21:mads/mads21:related', '//mads21:name[@type="meeting"]', '/mads21:related/@type', NULL, NULL )
,( 'geographic_name', 'main',    'Main Geographic Term',    '/mads21:mads/mads21:authority', '//mads21:geographic', NULL, '/mads21:mads/mads21:authority/mads21:geographic[1]/@authority', NULL )
,( 'geographic_name', 'variant', 'Variant Geographic Term', '/mads21:mads/mads21:variant',   '//mads21:geographic', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:geographic[1]/@authority', '//mads21:geographic[1]/@authority')
,( 'geographic_name', 'related', 'Related Geographic Term', '/mads21:mads/mads21:related',   '//mads21:geographic', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:geographic[1]/@authority', '//mads21:geographic[1]/@authority')
,( 'genre_form_term', 'main',    'Main Genre/Form Term',    '/mads21:mads/mads21:authority', '//mads21:genre', NULL, '/mads21:mads/mads21:authority/mads21:genre[1]/@authority', NULL )
,( 'genre_form_term', 'variant', 'Variant Genre/Form Term', '/mads21:mads/mads21:variant',   '//mads21:genre', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:genre[1]/@authority', '//mads21:genre[1]/@authority')
,( 'genre_form_term', 'related', 'Related Genre/Form Term', '/mads21:mads/mads21:related',   '//mads21:genre', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:genre[1]/@authority', '//mads21:genre[1]/@authority')
,( 'chronological_term', 'main',    'Main Chronological Term',    '/mads21:mads/mads21:authority', '//mads21:temporal', NULL, '/mads21:mads/mads21:authority/mads21:temporal[1]/@authority', NULL )
,( 'chronological_term', 'variant', 'Variant Chronological Term', '/mads21:mads/mads21:variant',   '//mads21:temporal', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:temporal[1]/@authority', '//mads21:temporal[1]/@authority')
,( 'chronological_term', 'related', 'Related Chronological Term', '/mads21:mads/mads21:related',   '//mads21:temporal', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:temporal[1]/@authority', '//mads21:temporal[1]/@authority')
,( 'uniform_title', 'main',    'Main Uniform Title',    '/mads21:mads/mads21:authority', '//mads21:title', NULL, '/mads21:mads/mads21:authority/mads21:title[1]/@authority', NULL )
,( 'uniform_title', 'variant', 'Variant Uniform Title', '/mads21:mads/mads21:variant',   '//mads21:title', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:title[1]/@authority', '//mads21:title[1]/@authority')
,( 'uniform_title', 'related', 'Related Uniform Title', '/mads21:mads/mads21:related',   '//mads21:title', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:title[1]/@authority', '//mads21:title[1]/@authority')
;

-- NACO normalize all the things
INSERT INTO authority.heading_field_norm_map (field, norm, pos)
SELECT id, 1, 0
FROM authority.heading_field;

CREATE TYPE authority.heading AS (
    field               INT,
    type                authority.heading_type,
    purpose             authority.heading_purpose,
    variant_type        authority.variant_heading_type,
    related_type        authority.related_heading_type,
    thesaurus           TEXT,
    heading             TEXT,
    normalized_heading  TEXT
);

CREATE OR REPLACE FUNCTION authority.extract_headings(marc TEXT, restrict INT[] DEFAULT NULL) RETURNS SETOF authority.heading AS $func$
DECLARE
    idx         authority.heading_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    heading_node    TEXT;
    heading_node_list   TEXT[];
    component_node    TEXT;
    component_node_list   TEXT[];
    raw_text    TEXT;
    normalized_text    TEXT;
    normalizer  RECORD;
    curr_text   TEXT;
    joiner      TEXT;
    type_value  TEXT;
    base_thesaurus TEXT := NULL;
    output_row  authority.heading;
BEGIN

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM authority.heading_field WHERE restrict IS NULL OR id = ANY (restrict) ORDER BY format LOOP

        output_row.field   := idx.id;
        output_row.type    := idx.heading_type;
        output_row.purpose := idx.heading_purpose;

        joiner := COALESCE(idx.joiner, ' ');

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(marc, xfrm.xslt);
            ELSE
                transformed_xml := marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        IF idx.thesaurus_xpath IS NOT NULL THEN
            base_thesaurus := ARRAY_TO_STRING(oils_xpath(idx.thesaurus_xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
        END IF;

        heading_node_list := oils_xpath( idx.heading_xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        FOR heading_node IN SELECT x FROM unnest(heading_node_list) AS x LOOP

            CONTINUE WHEN heading_node !~ E'^\\s*<';

            output_row.variant_type := NULL;
            output_row.related_type := NULL;
            output_row.thesaurus    := NULL;
            output_row.heading      := NULL;

            IF idx.heading_purpose = 'variant' AND idx.type_xpath IS NOT NULL THEN
                type_value := ARRAY_TO_STRING(oils_xpath(idx.type_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
                BEGIN
                    output_row.variant_type := type_value;
                EXCEPTION WHEN invalid_text_representation THEN
                    RAISE NOTICE 'Do not recognize variant heading type %', type_value;
                END;
            END IF;
            IF idx.heading_purpose = 'related' AND idx.type_xpath IS NOT NULL THEN
                type_value := ARRAY_TO_STRING(oils_xpath(idx.type_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
                BEGIN
                    output_row.related_type := type_value;
                EXCEPTION WHEN invalid_text_representation THEN
                    RAISE NOTICE 'Do not recognize related heading type %', type_value;
                END;
            END IF;
 
            IF idx.thesaurus_override_xpath IS NOT NULL THEN
                output_row.thesaurus := ARRAY_TO_STRING(oils_xpath(idx.thesaurus_override_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
            END IF;
            IF output_row.thesaurus IS NULL THEN
                output_row.thesaurus := base_thesaurus;
            END IF;

            raw_text := NULL;

            -- now iterate over components of heading
            component_node_list := oils_xpath( idx.component_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
            FOR component_node IN SELECT x FROM unnest(component_node_list) AS x LOOP
            -- XXX much of this should be moved into oils_xpath_string...
                curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                    oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                        REGEXP_REPLACE( component_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                    ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                    joiner
                );

                CONTINUE WHEN curr_text IS NULL OR curr_text = '';

                IF raw_text IS NOT NULL THEN
                    raw_text := raw_text || joiner;
                END IF;

                raw_text := COALESCE(raw_text,'') || curr_text;
            END LOOP;

            IF raw_text IS NOT NULL THEN
                output_row.heading := raw_text;
                normalized_text := raw_text;

                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                    FROM  config.index_normalizer n
                            JOIN authority.heading_field_norm_map m ON (m.norm = n.id)
                    WHERE m.field = idx.id
                    ORDER BY m.pos LOOP
            
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( normalized_text ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO normalized_text;
            
                END LOOP;
            
                output_row.normalized_heading := normalized_text;
            
                RETURN NEXT output_row;
            END IF;
        END LOOP;

    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.extract_headings(rid BIGINT, restrict INT[] DEFAULT NULL) RETURNS SETOF authority.heading AS $func$
DECLARE
    auth        authority.record_entry%ROWTYPE;
    output_row  authority.heading;
BEGIN
    -- Get the record
    SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

    RETURN QUERY SELECT * FROM authority.extract_headings(auth.marc, restrict);
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    heading_row     authority.heading%ROWTYPE;
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
    res.thesaurus := authority.extract_thesaurus(marcxml);

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP
        res.atag := acsaf.id;

        IF acsaf.heading_field IS NULL THEN
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
        ELSE
            FOR heading_row IN SELECT * FROM authority.extract_headings(marcxml, ARRAY[acsaf.heading_field]) LOOP
                res.value := heading_row.heading;
                res.sort_value := heading_row.normalized_heading;
                res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                RETURN NEXT res;
            END LOOP;
        END IF;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

ALTER TABLE authority.control_set_authority_field ADD COLUMN heading_field INTEGER REFERENCES authority.heading_field(id);

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '100'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'personal_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '400'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'personal_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '500'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'personal_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '110'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'corporate_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '410'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'corporate_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '510'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'corporate_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '111'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'meeting_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '411'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'meeting_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '511'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'meeting_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '130'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'uniform_title';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '430'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'uniform_title';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '530'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'uniform_title';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '150'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'topical_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '450'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'topical_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '550'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'topical_term';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '151'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'geographic_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '451'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'geographic_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '551'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'geographic_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '155'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'genre_form_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '455'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'genre_form_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '555'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'genre_form_term';

COMMIT;

-- Evergreen DB patch 0837.schema.browse-auth-linking.plus-joiner.sql
--
-- In this upgrade script we complete inter-subfield joiner support, so that
-- subject components can be separated by " -- ", for instance.  That's the
-- easy part.
--
-- We also add the ability to browse by in-use authority main entries and find
-- bibs that use unauthorized versions of the authority's value, by string matching.
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0837', :eg_version);

ALTER TABLE config.metabib_field ADD COLUMN joiner TEXT;
UPDATE config.metabib_field SET joiner = ' -- ' WHERE field_class = 'subject' AND name NOT IN ('name', 'complete');

-- To avoid problems with altering a table column after doing an
-- update.
ALTER TABLE authority.control_set_authority_field DISABLE TRIGGER ALL;

ALTER TABLE authority.control_set_authority_field ADD COLUMN joiner TEXT;
UPDATE authority.control_set_authority_field SET joiner = ' -- ' WHERE tag LIKE ANY (ARRAY['_4_','_5_','_8_']);

ALTER TABLE authority.control_set_authority_field ENABLE TRIGGER ALL;

-- Seed data will be generated from class <-> axis mapping
CREATE TABLE authority.control_set_bib_field_metabib_field_map (
    id              SERIAL  PRIMARY KEY,
    bib_field       INT     NOT NULL REFERENCES authority.control_set_bib_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    metabib_field   INT     NOT NULL REFERENCES config.metabib_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT a_bf_mf_map_once UNIQUE (bib_field, metabib_field)
);

CREATE VIEW authority.control_set_auth_field_metabib_field_map_main AS
    SELECT  DISTINCT b.authority_field, m.metabib_field
      FROM  authority.control_set_bib_field_metabib_field_map m JOIN authority.control_set_bib_field b ON (b.id = m.bib_field);
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_main IS $$metabib fields for main entry auth fields$$;

CREATE VIEW authority.control_set_auth_field_metabib_field_map_refs_only AS
    SELECT  DISTINCT a.id AS authority_field, m.metabib_field
      FROM  authority.control_set_authority_field a
            JOIN authority.control_set_authority_field ame ON (a.main_entry = ame.id)
            JOIN authority.control_set_bib_field b ON (b.authority_field = ame.id)
            JOIN authority.control_set_bib_field_metabib_field_map mf ON (mf.bib_field = b.id)
            JOIN authority.control_set_auth_field_metabib_field_map_main m ON (ame.id = m.authority_field);
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_refs_only IS $$metabib fields for NON-main entry auth fields$$;

CREATE VIEW authority.control_set_auth_field_metabib_field_map_refs AS
    SELECT * FROM authority.control_set_auth_field_metabib_field_map_main
        UNION
    SELECT * FROM authority.control_set_auth_field_metabib_field_map_refs_only;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_refs IS $$metabib fields for all auth fields$$;


-- blind refs only is probably what we want for lookup in bib/auth browse
CREATE VIEW authority.control_set_auth_field_metabib_field_map_blind_refs_only AS
    SELECT  r.*
      FROM  authority.control_set_auth_field_metabib_field_map_refs_only r
            JOIN authority.control_set_authority_field a ON (r.authority_field = a.id)
      WHERE linking_subfield IS NULL;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_blind_refs_only IS $$metabib fields for NON-main entry auth fields that can't be linked to other records$$; -- '

CREATE VIEW authority.control_set_auth_field_metabib_field_map_blind_refs AS
    SELECT  r.*
      FROM  authority.control_set_auth_field_metabib_field_map_refs r
            JOIN authority.control_set_authority_field a ON (r.authority_field = a.id)
      WHERE linking_subfield IS NULL;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_blind_refs IS $$metabib fields for all auth fields that can't be linked to other records$$; -- '

CREATE VIEW authority.control_set_auth_field_metabib_field_map_blind_main AS
    SELECT  r.*
      FROM  authority.control_set_auth_field_metabib_field_map_main r
            JOIN authority.control_set_authority_field a ON (r.authority_field = a.id)
      WHERE linking_subfield IS NULL;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_blind_main IS $$metabib fields for main entry auth fields that can't be linked to other records$$; -- '

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT, no_thesaurus BOOL ) RETURNS TEXT AS $func$
DECLARE
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    sf_node         TEXT;
    tag_node        TEXT;
    thes_code       TEXT;
    cset            INT;
    heading_text    TEXT;
    tmp_text        TEXT;
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

    thes_code := vandelay.marc21_extract_fixed_field(marcxml,'Subj');
    IF thes_code IS NULL THEN
        thes_code := '|';
    ELSIF thes_code = 'z' THEN
        thes_code := COALESCE( oils_xpath_string('//*[@tag="040"]/*[@code="f"][1]', marcxml), '' );
    END IF;

    heading_text := '';
    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset AND main_entry IS NULL LOOP
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        first_sf := TRUE;

        FOR tag_node IN SELECT unnest(oils_xpath('//*[@tag="'||tag_used||'"]',marcxml)) LOOP
            FOR sf_node IN SELECT unnest(oils_xpath('./*[contains("'||acsaf.sf_list||'",@code)]',tag_node)) LOOP

                tmp_text := oils_xpath_string('.', sf_node);
                sf := oils_xpath_string('./@code', sf_node);

                IF first_sf AND tmp_text IS NOT NULL AND nfi_used IS NOT NULL THEN

                    tmp_text := SUBSTRING(
                        tmp_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('./@ind'||nfi_used, tag_node),
                                    $$\D+$$,
                                    '',
                                    'g'
                                ),
                                ''
                            )::INT,
                            0
                        ) + 1
                    );

                END IF;

                first_sf := FALSE;

                IF tmp_text IS NOT NULL AND tmp_text <> '' THEN
                    heading_text := heading_text || E'\u2021' || sf || ' ' || tmp_text;
                END IF;
            END LOOP;

            EXIT WHEN heading_text <> '';
        END LOOP;

        EXIT WHEN heading_text <> '';
    END LOOP;

    IF heading_text <> '' THEN
        IF no_thesaurus IS TRUE THEN
            heading_text := tag_used || ' ' || public.naco_normalize(heading_text);
        ELSE
            heading_text := tag_used || '_' || COALESCE(nfi_used,'-') || '_' || thes_code || ' ' || public.naco_normalize(heading_text);
        END IF;
    ELSE
        heading_text := 'NOHEADING_' || thes_code || ' ' || MD5(marcxml);
    END IF;

    RETURN heading_text;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    joiner_text    TEXT;
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

        FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)) LOOP

            heading_text := COALESCE(
                oils_xpath_string('./*[contains("'||acsaf.sf_list||'",@code)]', tmp_xml::TEXT, joiner_text),
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

CREATE TABLE metabib.browse_entry_simple_heading_map (
    id BIGSERIAL PRIMARY KEY,
    entry BIGINT REFERENCES metabib.browse_entry (id),
    simple_heading BIGINT REFERENCES authority.simple_heading (id) ON DELETE CASCADE
);
CREATE INDEX browse_entry_sh_map_entry_idx ON metabib.browse_entry_simple_heading_map (entry);
CREATE INDEX browse_entry_sh_map_sh_idx ON metabib.browse_entry_simple_heading_map (simple_heading);

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
                oils_xpath( '//text()',
                    REGEXP_REPLACE(
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
                        ),
                        E'\\s+',
                        ' ',
                        'g'
                    )
                ), ' '), ''),
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
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
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

CREATE OR REPLACE
    FUNCTION metabib.autosuggest_prepare_tsquery(orig TEXT) RETURNS TEXT[] AS
$$
DECLARE
    orig_ended_in_space     BOOLEAN;
    result                  RECORD;
    plain                   TEXT;
    normalized              TEXT;
BEGIN
    orig_ended_in_space := orig ~ E'\\s$';

    orig := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(orig, E'\\W+'), ' '
    );

    normalized := public.naco_normalize(orig); -- also trim()s
    plain := trim(orig);

    IF NOT orig_ended_in_space THEN
        plain := plain || ':*';
        normalized := normalized || ':*';
    END IF;

    plain := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(plain, E'\\s+'), ' & '
    );
    normalized := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(normalized, E'\\s+'), ' & '
    );

    RETURN ARRAY[normalized, plain];
END;
$$ LANGUAGE PLPGSQL;

ALTER TYPE metabib.flat_browse_entry_appearance ADD ATTRIBUTE sees TEXT;
ALTER TYPE metabib.flat_browse_entry_appearance ADD ATTRIBUTE asources INT;
ALTER TYPE metabib.flat_browse_entry_appearance ADD ATTRIBUTE aaccurate TEXT;

CREATE OR REPLACE FUNCTION metabib.browse_bib_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  mbe.id
      FROM  metabib.browse_entry mbe
            JOIN metabib.browse_entry_def_map mbedm ON (
                mbedm.entry = mbe.id
                AND mbedm.def = ANY($1)
            )
      WHERE mbe.sort_value >= public.naco_normalize($2)
      ORDER BY mbe.sort_value, mbe.value LIMIT 1;
$p$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.browse_authority_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  mbe.id
      FROM  metabib.browse_entry mbe
            JOIN metabib.browse_entry_simple_heading_map mbeshm ON ( mbeshm.entry = mbe.id )
            JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
            JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                ash.atag = map.authority_field
                AND map.metabib_field = ANY($1)
            )
      WHERE mbe.sort_value >= public.naco_normalize($2)
      ORDER BY mbe.sort_value, mbe.value LIMIT 1;
$p$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.browse_authority_refs_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  mbe.id
      FROM  metabib.browse_entry mbe
            JOIN metabib.browse_entry_simple_heading_map mbeshm ON ( mbeshm.entry = mbe.id )
            JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
            JOIN authority.control_set_auth_field_metabib_field_map_refs_only map ON (
                ash.atag = map.authority_field
                AND map.metabib_field = ANY($1)
            )
      WHERE mbe.sort_value >= public.naco_normalize($2)
      ORDER BY mbe.sort_value, mbe.value LIMIT 1;
$p$ LANGUAGE SQL;

-- The drop is necessary because the language change from PLPGSQL to SQL
-- carries with it name changes to the parameters
DROP FUNCTION metabib.browse_pivot(INT[], TEXT);
CREATE FUNCTION metabib.browse_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  id FROM metabib.browse_entry
      WHERE id IN (
                metabib.browse_bib_pivot($1, $2),
                metabib.browse_authority_refs_pivot($1,$2) -- only look in 4xx, 5xx, 7xx of authority
            )
      ORDER BY sort_value, value LIMIT 1;
$p$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.staged_browse(
    query                   TEXT,
    fields                  INT[],
    context_org             INT,
    context_locations       INT[],
    staff                   BOOL,
    browse_superpage_size   INT,
    count_up_from_zero      BOOL,   -- if false, count down from -1
    result_limit            INT,
    next_pivot_pos          INT
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    OPEN curs FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;


        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        SELECT INTO all_arecords, result_row.sees, afields
                ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                ARRAY_TO_STRING(ARRAY_AGG(DISTINCT aal.source), $$,$$), -- authority record ids
                ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

          FROM  metabib.browse_entry_simple_heading_map mbeshm
                JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    ash.atag = map.authority_field
                    AND map.metabib_field = ANY(fields)
                )
          WHERE mbeshm.entry = rec.id;


        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                ARRAY_TO_STRING(ARRAY_AGG(DISTINCT authority), $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields ARRAY_TO_STRING(ARRAY_AGG(DISTINCT x), $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_brecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.sources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_brecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    '1::INT AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, until we've
                -- either exhausted that set of records or found at least 1
                -- visible record.

                SELECT INTO result_row.sources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;

            -- Accurate?  Well, probably.
            result_row.accurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_arecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.asources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_arecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    '1::INT AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, via
                -- authority until we've either exhausted that set of records
                -- or found at least 1 visible record.

                SELECT INTO result_row.asources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;


            -- Accurate?  Well, probably.
            result_row.aaccurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$p$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.browse(
    search_field            INT[],
    browse_term             TEXT,
    context_org             INT DEFAULT NULL,
    context_loc_group       INT DEFAULT NULL,
    staff                   BOOL DEFAULT FALSE,
    pivot_id                BIGINT DEFAULT NULL,
    result_limit            INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size value     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
SELECT  mbe.id,
        mbe.value,
        mbe.sort_value
  FROM  metabib.browse_entry mbe
  WHERE (
            EXISTS ( -- are there any bibs using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_def_map mbedm
                  WHERE mbedm.entry = mbe.id AND mbedm.def = ANY(' || quote_literal(search_field) || ')
                  LIMIT 1
            ) OR EXISTS ( -- are there any authorities using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_simple_heading_map mbeshm
                        JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                        JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                            ash.atag = map.authority_field
                            AND map.metabib_field = ANY(' || quote_literal(search_field) || ')
                        )
                  WHERE mbeshm.entry = mbe.id
            )
        ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC ';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value ';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$p$ LANGUAGE PLPGSQL;

-- No 4XX inter-authority linking
UPDATE authority.control_set_authority_field SET linking_subfield = NULL;
UPDATE authority.control_set_authority_field SET linking_subfield = '0' WHERE tag LIKE ANY (ARRAY['5%','7%']);

-- Map between authority controlled bib fields and stock indexing metabib fields
INSERT INTO authority.control_set_bib_field_metabib_field_map (bib_field, metabib_field)
    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '100' AND m.name = 'personal'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '110' AND m.name = 'corporate'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '111' AND m.name = 'conference'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '130' AND m.name = 'uniform'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '148' AND m.name = 'temporal'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '150' AND m.name = 'topic'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '151' AND m.name = 'geographic'

        UNION

    SELECT  DISTINCT b.id AS bib_field, m.id AS metabib_field
      FROM  authority.control_set_bib_field b JOIN authority.control_set_authority_field a ON (b.authority_field = a.id), config.metabib_field m
      WHERE a.tag = '155' AND m.name = 'genre' -- Just in case...
;

CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    ashs    authority.simple_heading%ROWTYPE;
    mbe_row metabib.browse_entry%ROWTYPE;
    mbe_id  BIGINT;
    ash_id  BIGINT;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
        DELETE FROM authority.simple_heading WHERE record = NEW.id;
          -- Should remove matching $0 from controlled fields at the same time?

        -- XXX What do we about the actual linking subfields present in
        -- authority records that target this one when this happens?
        DELETE FROM authority.authority_linking
            WHERE source = NEW.id OR target = NEW.id;

        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;

        -- Propagate these updates to any linked bib records
        PERFORM authority.propagate_changes(NEW.id) FROM authority.record_entry WHERE id = NEW.id;

        DELETE FROM authority.simple_heading WHERE record = NEW.id;
        DELETE FROM authority.authority_linking WHERE source = NEW.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            NEW.id, NEW.control_set, NEW.marc::XML
        );

    FOR ashs IN SELECT * FROM authority.simple_heading_set(NEW.marc) LOOP

        INSERT INTO authority.simple_heading (record,atag,value,sort_value)
            VALUES (ashs.record, ashs.atag, ashs.value, ashs.sort_value);
        ash_id := CURRVAL('authority.simple_heading_id_seq'::REGCLASS);

        SELECT INTO mbe_row * FROM metabib.browse_entry
            WHERE value = ashs.value AND sort_value = ashs.sort_value;

        IF FOUND THEN
            mbe_id := mbe_row.id;
        ELSE
            INSERT INTO metabib.browse_entry
                ( value, sort_value ) VALUES
                ( ashs.value, ashs.sort_value );

            mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
        END IF;

        INSERT INTO metabib.browse_entry_simple_heading_map (entry,simple_heading) VALUES (mbe_id,ash_id);

    END LOOP;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(NEW.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(NEW.id);
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;


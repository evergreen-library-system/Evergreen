BEGIN;

SELECT evergreen.upgrade_deps_block_check('1134', :eg_version);

CREATE OR REPLACE FUNCTION metabib.staged_browse(query text, fields integer[], context_org integer, context_locations integer[], staff boolean, browse_superpage_size integer, count_up_from_zero boolean, result_limit integer, next_pivot_pos integer)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
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
    c_tests                 TEXT := '';
    b_tests                 TEXT := '';
    c_orgs                  INT[];
    unauthorized_entry      RECORD;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    IF NOT staff THEN
        SELECT x.c_attrs, x.b_attrs INTO c_tests, b_tests FROM asset.patron_default_visibility_mask() x;
    END IF;

    -- b_tests supplies its own query_int operator, c_tests does not
    IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;

    SELECT ARRAY_AGG(id) INTO c_orgs FROM actor.org_unit_descendants(context_org);

    c_tests := c_tests || search.calculate_visibility_attribute_test('circ_lib',c_orgs)
               || '&' || search.calculate_visibility_attribute_test('owning_lib',c_orgs);

    PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
    IF FOUND THEN
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(context_org) x)
        );
    ELSE
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(context_org) x)
        );
    END IF;

    IF context_locations THEN
        IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
        c_tests := c_tests || search.calculate_visibility_attribute_test('location',context_locations);
    END IF;

    OPEN curs NO SCROLL FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;

        --Is unauthorized?
        SELECT INTO unauthorized_entry *
        FROM metabib.browse_entry_simple_heading_map mbeshm
        INNER JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
        INNER JOIN authority.control_set_authority_field acsaf ON ( acsaf.id = ash.atag )
        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
        WHERE mbeshm.entry = rec.id
        AND   ahf.heading_purpose = 'variant';

        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        IF (unauthorized_entry.record IS NOT NULL) THEN
            --unauthorized term belongs to an auth linked to a bib?
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib),
                    STRING_AGG(DISTINCT abl.authority::TEXT, $$,$$),
                    ARRAY_AGG(DISTINCT map.metabib_field)
            FROM authority.bib_linking abl
            INNER JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    map.authority_field = unauthorized_entry.atag
                    AND map.metabib_field = ANY(fields)
            )
            WHERE abl.authority = unauthorized_entry.record;
        ELSE
            --do usual procedure
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                    STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                    ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

            FROM  metabib.browse_entry_simple_heading_map mbeshm
                    JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                    JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                    JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                    JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                        ash.atag = map.authority_field
                        AND map.metabib_field = ANY(fields)
                    )
                    JOIN authority.control_set_authority_field acsaf ON (
                        map.authority_field = acsaf.id
                    )
                    JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
              WHERE mbeshm.entry = rec.id
              AND   ahf.heading_purpose = 'variant';

        END IF;

        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.sources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_brecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.accurate := TRUE;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.asources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_arecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.aaccurate := TRUE;

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
$f$ LANGUAGE plpgsql ROWS 10;

COMMIT;

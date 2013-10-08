BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0839', :eg_version);

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:titleInfo[mods32:title and starts-with(@type,'alternative')]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL
WHERE
    field_class = 'title' AND name = 'alternative' ;

COMMIT;

-- The following function only appears in the upgrade script and not the
-- baseline schema because it's not necessary in the latter (and it's a
-- temporary function).  It just serves to do a hopefully cheaper, more
-- focused reingest just to hit the alternative title index.

-- This cribs from the guts of metabib.reingest_metabib_field_entries(),
-- and if it actually is a timesaver over a full reingest, then at some
-- point in the future it would be nice if we broke it out into a separate
-- function to make things like this easier.

CREATE OR REPLACE FUNCTION pg_temp.alternative_title_reingest( bib_id BIGINT ) RETURNS VOID AS $func$
DECLARE
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL := false;
    b_skip_browse   BOOL := false;
    b_skip_search   BOOL := false;
    alt_title       INT;
    value_prepped   TEXT;
BEGIN
    SELECT INTO alt_title id FROM config.metabib_field WHERE field_class = 'title' AND name = 'alternative';
    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) WHERE field = alt_title LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

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

        -- Avoid inserting duplicate rows, but retain granularity of being
        -- able to search browse fields with "starts with" type operators
        -- (for example, for titles of songs in music albums)
        IF (ind_data.search_field OR ind_data.browse_field) AND NOT b_skip_search THEN
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

\qecho This is a partial reingest of your bib records. It may take a while.

SELECT pg_temp.alternative_title_reingest(id) FROM biblio.record_entry WHERE NOT deleted;

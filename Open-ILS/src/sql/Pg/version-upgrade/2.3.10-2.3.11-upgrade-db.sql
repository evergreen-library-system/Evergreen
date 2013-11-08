--Upgrade Script for 2.3.10 to 2.3.11
\set eg_version '''2.3.11'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.3.11', :eg_version);

-- Remove [ and ] characters from seriestitle.
-- Those characters don't play well when searching.

SELECT evergreen.upgrade_deps_block_check('0820', :eg_version); -- Callender

INSERT INTO config.metabib_field_index_norm_map (field,norm,params, pos)
     SELECT  m.id,
             i.id,
             $$["]",""]$$,
             '-1'
       FROM  config.metabib_field m,
             config.index_normalizer i
       WHERE i.func IN ('replace')
             AND m.id IN (1);
             
INSERT INTO config.metabib_field_index_norm_map (field,norm,params, pos)
     SELECT  m.id,
             i.id,
             $$["[",""]$$,
             '-1'
       FROM  config.metabib_field m,
             config.index_normalizer i
       WHERE i.func IN ('replace')
             AND m.id IN (1);


SELECT evergreen.upgrade_deps_block_check('0821', :eg_version);

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    mbe_txt         TEXT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.
            mbe_txt := metabib.browse_normalize(ind_data.value, ind_data.field);
            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = mbe_txt;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES (mbe_txt);
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field AND NOT skip_search THEN
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


-- Evergreen DB patch 0825.data.bre_format.sql
--
-- Fix some templates that loop over bibs to not have duplicated/run-on titles
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0825', :eg_version);

-- I think we shy away from modifying templates on existing systems, but this seems pretty safe...
UPDATE
    action_trigger.event_definition
SET
    template = replace(template,'[% FOR cbreb IN target %]','[% FOR cbreb IN target %][% title = '''' %]')
WHERE
    id IN (31,32);

COMMIT;

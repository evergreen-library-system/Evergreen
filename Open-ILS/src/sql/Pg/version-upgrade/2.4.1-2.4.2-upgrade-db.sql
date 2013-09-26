--Upgrade Script for 2.4.1 to 2.4.2
\set eg_version '''2.4.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.4.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0818', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype ) VALUES (
    'circ.patron_edit.duplicate_patron_check_depth', 'circ',
    oils_i18n_gettext(
        'circ.patron_edit.duplicate_patron_check_depth',
        'Specify search depth for the duplicate patron check in the patron editor',
        'coust',
        'label'),
    oils_i18n_gettext(
        'circ.patron_edit.duplicate_patron_check_depth',
        'When using the patron registration page, the duplicate patron check will use the configured depth to scope the search for duplicate patrons.',
        'coust',
        'description'),
    'integer')
;



-- Evergreen DB patch 0819.schema.acn_dewey_normalizer.sql
--
-- Fixes Dewey call number sorting (per LP# 1150939)
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0819', :eg_version);

CREATE OR REPLACE FUNCTION asset.label_normalizer_dewey(TEXT) RETURNS TEXT AS $func$
    # Derived from the Koha C4::ClassSortRoutine::Dewey module
    # Copyright (C) 2007 LibLime
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    my $init = uc(shift);
    $init =~ s/^\s+//;
    $init =~ s/\s+$//;
    $init =~ s!/!!g;
    $init =~ s/^([\p{IsAlpha}]+)/$1 /;
    my @tokens = split /\.|\s+/, $init;
    my $digit_group_count = 0;
    my $first_digit_group_idx;
    for (my $i = 0; $i <= $#tokens; $i++) {
        if ($tokens[$i] =~ /^\d+$/) {
            $digit_group_count++;
            if ($digit_group_count == 1) {
                $first_digit_group_idx = $i;
            }
            if (2 == $digit_group_count) {
                $tokens[$i] = sprintf("%-15.15s", $tokens[$i]);
                $tokens[$i] =~ tr/ /0/;
            }
        }
    }
    # Pad the first digit_group if there was only one
    if (1 == $digit_group_count) {
        $tokens[$first_digit_group_idx] .= '_000000000000000'
    }
    my $key = join("_", @tokens);
    $key =~ s/[^\p{IsAlnum}_]//g;

    return $key;

$func$ LANGUAGE PLPERLU;

-- regenerate sort keys for any dewey call numbers
UPDATE asset.call_number SET id = id WHERE label_class = 2;


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
    b_skip_facet    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
BEGIN

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

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
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
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


COMMIT;

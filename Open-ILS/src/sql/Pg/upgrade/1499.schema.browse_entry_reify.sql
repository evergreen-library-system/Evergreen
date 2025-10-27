BEGIN;

SELECT evergreen.upgrade_deps_block_check('1499', :eg_version);

CREATE OR REPLACE FUNCTION metabib.disable_browse_entry_reification () RETURNS VOID AS $f$
    INSERT INTO config.internal_flag (name,enabled)
      VALUES ('ingest.disable_browse_entry_reification',TRUE)
    ON CONFLICT (name) DO UPDATE SET enabled = TRUE;
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.enable_browse_entry_reification () RETURNS VOID AS $f$
    UPDATE config.internal_flag SET enabled = FALSE WHERE name = 'ingest.disable_browse_entry_reification';
$f$ LANGUAGE SQL;


-- INSERT-only table that catches browse entry updates to be reconciled
CREATE UNLOGGED TABLE metabib.browse_entry_updates (
    transaction_id  BIGINT,
    simple_heading  BIGINT,
    source          BIGINT,
    authority       BIGINT,
    def             INT,
    sort_value      TEXT,
    value           TEXT
);
CREATE INDEX browse_entry_updates_tid_idx ON metabib.browse_entry_updates (transaction_id);

CREATE OR REPLACE FUNCTION metabib.browse_entry_reify (full_reify BOOLEAN DEFAULT FALSE) RETURNS INT AS $f$
  WITH new_authority_rows AS ( -- gather provisional authority browse entries
      DELETE FROM metabib.browse_entry_updates
        WHERE simple_heading IS NOT NULL AND (full_reify OR transaction_id = txid_current())
        RETURNING sort_value, value, simple_heading
  ), new_bib_rows AS ( -- gather provisional bib browse entries
      DELETE FROM metabib.browse_entry_updates
        WHERE def IS NOT NULL AND (full_reify OR transaction_id = txid_current())
        RETURNING sort_value, value, def, source, authority
  ), computed_browse_values AS ( -- unique set of to-be-mapped sort_value/value pairs :: sort_value, value, def, cmf.browse_nocase
      SELECT  nbr.sort_value, nbr.value, nbr.def, cmf.browse_nocase
        FROM  new_bib_rows AS nbr JOIN config.metabib_field AS cmf ON (nbr.def = cmf.id)
          UNION
      SELECT  sort_value, value, NULL::INT AS def, FALSE AS browse_nocase
        FROM new_authority_rows
  ), existing_browse_entries AS ( -- find the id of existing sort_value/value pairs, nocase'd if cmf says so :: id, sort_value, value, def (NULL for authority)
      SELECT  mbe.id, cr.sort_value, cr.value, cr.def
        FROM  metabib.browse_entry mbe
              JOIN computed_browse_values cr ON (
                  mbe.sort_value = cr.sort_value
                  AND (
                    (cr.browse_nocase AND evergreen.lowercase(mbe.value) = evergreen.lowercase(cr.value))
                    OR (NOT cr.browse_nocase AND mbe.value = cr.value)
                  )
              )
  ), missing_browse_entries AS ( -- unique set of sort_value/value pairs NOT in the browse_entry table
      SELECT DISTINCT sort_value, value FROM computed_browse_values
          EXCEPT
      SELECT sort_value, value FROM existing_browse_entries
  ), inserted_browse_entries AS ( -- insert missing sort_value/value pairs and get the new id for each
      INSERT INTO metabib.browse_entry (sort_value, value)
          SELECT sort_value, value FROM missing_browse_entries ON CONFLICT DO NOTHING RETURNING id, sort_value, value
  ), computed_browse_entries AS ( -- full set of to-be-mapped sort_value/value pairs with the id for each
      SELECT id, sort_value, value, def FROM existing_browse_entries
          UNION ALL
      SELECT id, sort_value, value, NULL::INT def FROM inserted_browse_entries
  ), new_authority_browse_map AS ( -- insert entry->simple_heading map now that all sort_value/value pairs have an id
      INSERT INTO metabib.browse_entry_simple_heading_map (entry, simple_heading)
          SELECT  cbe.id, nar.simple_heading
            FROM  computed_browse_entries cbe
                  JOIN new_authority_rows nar USING (sort_value, value)
      RETURNING *
  ), new_bib_browse_map AS ( -- insert entry->dev/source/authority map now that all sort_value/value pairs have an id
      INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
          SELECT  cbe.id, nbr.def, nbr.source, nbr.authority
            FROM  computed_browse_entries cbe
                  JOIN new_bib_rows nbr USING (sort_value, value, def)
            WHERE cbe.def IS NOT NULL
              UNION
          SELECT  cbe.id, nbr.def, nbr.source, nbr.authority
            FROM  computed_browse_entries cbe
                  JOIN new_bib_rows nbr USING (sort_value, value)
            WHERE cbe.def IS NULL
      RETURNING *
  )
  SELECT  a.row_count + b.row_count
    FROM  (SELECT COUNT(*) AS row_count FROM new_authority_browse_map) AS a,
          (SELECT COUNT(*) AS row_count FROM new_bib_browse_map) AS b;
$f$ LANGUAGE SQL;

-- This version does not constrain itself to just the current transaction.
CREATE OR REPLACE FUNCTION metabib.browse_entry_full_reify () RETURNS INT AS $f$
    SELECT metabib.browse_entry_reify(TRUE);
$f$ LANGUAGE SQL;

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
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id || $$ AND field = ANY($1)$$ USING field_list;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id AND field = ANY(field_list);
        END IF;
        IF NOT b_skip_display THEN
            DELETE FROM metabib.display_entry WHERE source = bib_id AND field = ANY(field_list);
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id AND def = ANY(field_list);
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

            CONTINUE WHEN ind_data.sort_value IS NULL;

            INSERT INTO metabib.browse_entry_updates (transaction_id, sort_value, value, def, source, authority)
                VALUES (txid_current(), SUBSTRING(ind_data.sort_value FOR 1000), SUBSTRING(metabib.browse_normalize(ind_data.value, ind_data.field) FOR 1000),
                        ind_data.field, ind_data.source, ind_data.authority);

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
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_symspell_reification' AND enabled;
        IF NOT FOUND THEN
            PERFORM search.symspell_dictionary_reify();
        END IF;
    END IF;

    IF NOT b_skip_browse THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_browse_entry_reification' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.browse_entry_reify();
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.indexing_update (auth authority.record_entry, insert_only BOOL DEFAULT FALSE, old_heading TEXT DEFAULT NULL) RETURNS BOOL AS $func$
DECLARE
    ashs    authority.simple_heading%ROWTYPE;
    mbe_row metabib.browse_entry%ROWTYPE;
    mbe_id  BIGINT;
    ash_id  BIGINT;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN

    -- Unless there's a setting stopping us, propagate these updates to any linked bib records when the heading changes
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_auto_update' AND enabled;

    IF NOT FOUND AND auth.heading <> old_heading THEN
        PERFORM authority.propagate_changes(auth.id);
    END IF;

    IF NOT insert_only THEN
        DELETE FROM authority.authority_linking WHERE source = auth.id;
        DELETE FROM authority.simple_heading WHERE record = auth.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            auth.id, auth.control_set, auth.marc::XML
        );

    FOR ashs IN SELECT * FROM authority.simple_heading_set(auth.marc) LOOP

        INSERT INTO authority.simple_heading (record,atag,value,sort_value,thesaurus)
            VALUES (ashs.record, ashs.atag, ashs.value, ashs.sort_value, ashs.thesaurus);
            ash_id := CURRVAL('authority.simple_heading_id_seq'::REGCLASS);

        INSERT INTO metabib.browse_entry_updates (transaction_id, sort_value, value, simple_heading)
            VALUES (txid_current(), SUBSTRING(ashs.sort_value FOR 1000), SUBSTRING(ashs.value FOR 1000), ash_id);

    END LOOP;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(auth.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(auth.id);
        END IF;
    END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_symspell_reification' AND enabled;
    IF NOT FOUND THEN
        PERFORM search.symspell_dictionary_reify();
    END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_browse_entry_reification' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.browse_entry_reify();
    END IF;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;


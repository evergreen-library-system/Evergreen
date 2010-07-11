BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0330');

CREATE TABLE metabib.facet_entry (
        id              BIGSERIAL       PRIMARY KEY,
        source          BIGINT          NOT NULL,
        field           INT             NOT NULL,
        value           TEXT            NOT NULL
);

INSERT INTO metabib.facet_entry (source, field, value)
    SELECT source, field, value FROM (
        SELECT * FROM metabib.author_field_entry
            UNION ALL
        SELECT * FROM metabib.keyword_field_entry
            UNION ALL
        SELECT * FROM metabib.identifier_field_entry
            UNION ALL
        SELECT * FROM metabib.title_field_entry
            UNION ALL
        SELECT * FROM metabib.subject_field_entry
            UNION ALL
        SELECT * FROM metabib.series_field_entry
        )x
    WHERE x.index_vector = '';
        
DELETE FROM metabib.author_field_entry WHERE index_vector = '';
DELETE FROM metabib.keyword_field_entry WHERE index_vector = '';
DELETE FROM metabib.identifier_field_entry WHERE index_vector = '';
DELETE FROM metabib.title_field_entry WHERE index_vector = '';
DELETE FROM metabib.subject_field_entry WHERE index_vector = '';
DELETE FROM metabib.series_field_entry WHERE index_vector = '';

CREATE INDEX metabib_facet_entry_field_idx ON metabib.facet_entry (field);
CREATE INDEX metabib_facet_entry_value_idx ON metabib.facet_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_facet_entry_source_idx ON metabib.facet_entry (source);

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
BEGIN
    FOR fclass IN SELECT * FROM config.metabib_class LOOP
        -- RAISE NOTICE 'Emptying out %', fclass.name;
        EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
    END LOOP;

    DELETE FROM metabib.facet_entry WHERE source = bib_id;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        ELSE
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

COMMIT;


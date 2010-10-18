BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0411'); -- gmc

INSERT INTO config.internal_flag (name) VALUES ('ingest.assume_inserts_only');

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_rec_descriptor( bib_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        DELETE FROM metabib.rec_descriptor WHERE record = bib_id;
    END IF;
    INSERT INTO metabib.rec_descriptor (record, item_type, item_form, bib_level, control_type, enc_level, audience, lit_form, type_mat, cat_form, pub_status, item_lang, vr_format, date1, date2)
        SELECT  bib_id,
                biblio.marc21_extract_fixed_field( bib_id, 'Type' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Form' ),
                biblio.marc21_extract_fixed_field( bib_id, 'BLvl' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Ctrl' ),
                biblio.marc21_extract_fixed_field( bib_id, 'ELvl' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Audn' ),
                biblio.marc21_extract_fixed_field( bib_id, 'LitF' ),
                biblio.marc21_extract_fixed_field( bib_id, 'TMat' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Desc' ),
                biblio.marc21_extract_fixed_field( bib_id, 'DtSt' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Lang' ),
                (   SELECT  v.value
                      FROM  biblio.marc21_physical_characteristics( bib_id) p
                            JOIN config.marc21_physical_characteristic_subfield_map s ON (s.id = p.subfield)
                            JOIN config.marc21_physical_characteristic_value_map v ON (v.id = p.value)
                      WHERE p.ptype = 'v' AND s.subfield = 'e'    ),
                biblio.marc21_extract_fixed_field( bib_id, 'Date1'),
                biblio.marc21_extract_fixed_field( bib_id, 'Date2');

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_full_rec( bib_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        DELETE FROM metabib.real_full_rec WHERE record = bib_id;
    END IF;
    INSERT INTO metabib.real_full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM biblio.flatten_marc( bib_id );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        FOR fclass IN SELECT * FROM config.metabib_class LOOP
            -- RAISE NOTICE 'Emptying out %', fclass.name;
            EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
        END LOOP;
        DELETE FROM metabib.facet_entry WHERE source = bib_id;
    END IF;

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

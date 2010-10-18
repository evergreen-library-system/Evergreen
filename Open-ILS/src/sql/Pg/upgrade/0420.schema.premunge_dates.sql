BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0420'); -- miker

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
                LPAD(NULLIF(REGEXP_REPLACE(NULLIF(biblio.marc21_extract_fixed_field( bib_id, 'Date1'), ''), E'\\D', '0', 'g')::INT,0)::TEXT,4,'0'),
                LPAD(NULLIF(REGEXP_REPLACE(NULLIF(biblio.marc21_extract_fixed_field( bib_id, 'Date2'), ''), E'\\D', '9', 'g')::INT,9999)::TEXT,4,'0');

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

UPDATE  metabib.rec_descriptor
  SET   date1=LPAD(NULLIF(REGEXP_REPLACE(NULLIF(date1, ''), E'\\D', '0', 'g')::INT,0)::TEXT,4,'0'),
        date2=LPAD(NULLIF(REGEXP_REPLACE(NULLIF(date2, ''), E'\\D', '9', 'g')::INT,9999)::TEXT,4,'0');

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('XXXX'); -- miker

CREATE TABLE config.record_attr_definition (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL, -- I18N
    description TEXT,
    filter      BOOL    NOT NULL DEFAULT TRUE,  -- becomes QP filter if true
    sorter      BOOL    NOT NULL DEFAULT FALSE, -- becomes QP sort() axis if true

-- For pre-extracted fields. Takes the first occurance, uses naive subfield ordering
    tag         TEXT, -- LIKE format
    sf_list     TEXT, -- pile-o-values, like 'abcd' for a and b and c and d

-- This is used for both tag/sf and xpath entries
    joiner      TEXT,

-- For xpath-extracted attrs
    xpath       TEXT,
    format      TEXT    REFERENCES config.xml_transform (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    start_pos   INT,
    string_len  INT,

-- For fixed fields
    fixed_field TEXT, -- should exist in config.marc21_ff_pos_map.fixed_field

-- For phys-char fields
    phys_char_sf    INT REFERENCES config.marc21_physical_characteristic_subfield_map (id)
);

CREATE TABLE config.record_attr_index_norm_map (
    id      SERIAL  PRIMARY KEY,
    attr    TEXT    NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    params  TEXT,
    pos     INT     NOT NULL DEFAULT 0
);

CREATE TABLE config.coded_value_map (
    id          SERIAL  PRIMARY KEY,
    ctype       TEXT    NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    code        TEXT    NOT NULL,
    value       TEXT    NOT NULL,
    description TEXT
);

-- record attributes
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('alph','Alph','Alph');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('audience','Audn','Audn');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('bib_level','BLvl','BLvl');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('biog','Biog','Biog');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('conf','Conf','Conf');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('control_type','Ctrl','Ctrl');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('ctry','Ctry','Ctry');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('date1','Date1','Date1');
INSERT INTO config.record_attr_definition (name,label,fixed_field,sorter,filter) values ('pubdate','Pub Date','Date1',TRUE,FALSE);
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('date2','Date2','Date2');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('cat_form','Desc','Desc');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('pub_status','DtSt','DtSt');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('enc_level','ELvl','ELvl');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('fest','Fest','Fest');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('item_form','Form','Form');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('gpub','GPub','GPub');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('ills','Ills','Ills');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('indx','Indx','Indx');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('item_lang','Lang','Lang');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('lit_form','LitF','LitF');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('mrec','MRec','MRec');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('ff_sl','S/L','S/L');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('type_mat','TMat','TMat');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('item_type','Type','Type');
INSERT INTO config.record_attr_definition (name,label,phys_char_sf) values ('vr_format','Videorecording format',72);
INSERT INTO config.record_attr_definition (name,label,sorter,filter,tag) values ('titlesort','Title',TRUE,FALSE,'tnf');
INSERT INTO config.record_attr_definition (name,label,sorter,filter,tag) values ('authorsort','Author',TRUE,FALSE,'1%');

INSERT INTO config.coded_value_map (ctype,code,value,description)
    SELECT 'item_lang' AS ctype, code, value, NULL FROM config.language_map
        UNION
    SELECT 'bib_level' AS ctype, code, value, NULL FROM config.bib_level_map
        UNION
    SELECT 'item_form' AS ctype, code, value, NULL FROM config.item_form_map
        UNION
    SELECT 'item_type' AS ctype, code, value, NULL FROM config.item_type_map
        UNION
    SELECT 'lit_form' AS ctype, code, value, description FROM config.lit_form_map
        UNION
    SELECT 'audience' AS ctype, code, value, description FROM config.audience_map
        UNION
    SELECT 'vr_format' AS ctype, code, value, NULL FROM config.videorecording_format_map;

ALTER TABLE config.i18n_locale DROP CONSTRAINT i18n_locale_marc_code_fkey;

ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT circ_matrix_matchpoint_marc_form_fkey;
ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT circ_matrix_matchpoint_marc_type_fkey;
ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT circ_matrix_matchpoint_marc_vr_format_fkey;

ALTER TABLE config.hold_matrix_matchpoint DROP CONSTRAINT hold_matrix_matchpoint_marc_form_fkey;
ALTER TABLE config.hold_matrix_matchpoint DROP CONSTRAINT hold_matrix_matchpoint_marc_type_fkey;
ALTER TABLE config.hold_matrix_matchpoint DROP CONSTRAINT hold_matrix_matchpoint_marc_vr_format_fkey;

DROP TABLE config.language_map;
DROP TABLE config.bib_level_map;
DROP TABLE config.item_form_map;
DROP TABLE config.item_type_map;
DROP TABLE config.lit_form_map;
DROP TABLE config.audience_map;
DROP TABLE config.videorecording_format_map;

UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'clm.value' AND ccvm.ctype = 'item_lang' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cblvl.value' AND ccvm.ctype = 'bib_level' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cifm.value' AND ccvm.ctype = 'item_form' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'citm.value' AND ccvm.ctype = 'item_type' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'clfm.value' AND ccvm.ctype = 'lit_form' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cam.value' AND ccvm.ctype = 'audience' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cvrfm.value' AND ccvm.ctype = 'vr_format' AND identity_value = ccvm.code;

UPDATE config.i18n_core SET fq_field = 'ccvm.description', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'clfm.description' AND ccvm.ctype = 'lit_form' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.description', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cam.description' AND ccvm.ctype = 'audience' AND identity_value = ccvm.code;

CREATE VIEW config.language_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_lang';
CREATE VIEW config.bib_level_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'bib_level';
CREATE VIEW config.item_form_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_form';
CREATE VIEW config.item_type_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_type';
CREATE VIEW config.lit_form_map AS SELECT code, value, description FROM config.coded_value_map WHERE ctype = 'lit_form';
CREATE VIEW config.audience_map AS SELECT code, value, description FROM config.coded_value_map WHERE ctype = 'audience';
CREATE VIEW config.videorecording_format_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'vr_format';

CREATE TABLE metabib.record_attr (
       id              BIGINT  PRIMARY KEY REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
       attrs   HSTORE  NOT NULL DEFAULT ''::HSTORE
);
CREATE INDEX metabib_svf_attrs_idx ON metabib.record_attr USING GIST (attrs);
CREATE INDEX metabib_svf_date1_idx ON metabib.record_attr ( (attrs->'date1') );
CREATE INDEX metabib_svf_dates_idx ON metabib.record_attr ( (attrs->'date1'), (attrs->'date2') );

INSERT INTO metabib.record_attr (id,attrs)
    SELECT mrd.record, hstore(mrd) - '{id,record}'::TEXT[] FROM metabib.rec_descriptor mrd;

-- Back-compat view ... we're moving to an HSTORE world
CREATE TYPE metabib.rec_desc_type AS (
    item_type       TEXT,
    item_form       TEXT,
    bib_level       TEXT,
    control_type    TEXT,
    char_encoding   TEXT,
    enc_level       TEXT,
    audience        TEXT,
    lit_form        TEXT,
    type_mat        TEXT,
    cat_form        TEXT,
    pub_status      TEXT,
    item_lang       TEXT,
    vr_format       TEXT,
    date1           TEXT,
    date2           TEXT
);

DROP TABLE metabib.rec_descriptor CASCADE;

CREATE VIEW metabib.rec_descriptor AS
    SELECT  id,
            id AS record,
            (populate_record(NULL::metabib.rec_desc_type, attrs)).*
      FROM  metabib.record_attr;

CREATE OR REPLACE FUNCTION vandelay.marc21_record_type( marc TEXT ) RETURNS config.marc21_rec_type_map AS $func$
DECLARE
    ldr         TEXT;
    tval        TEXT;
    tval_rec    RECORD;
    bval        TEXT;
    bval_rec    RECORD;
    retval      config.marc21_rec_type_map%ROWTYPE;
BEGIN
    ldr := oils_xpath_string( '//*[local-name()="leader"]', marc );

    IF ldr IS NULL OR ldr = '' THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
        RETURN retval;
    END IF;

    SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
    SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


    tval := SUBSTRING( ldr, tval_rec.start_pos + 1, tval_rec.length );
    bval := SUBSTRING( ldr, bval_rec.start_pos + 1, bval_rec.length );

    -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr;

    SELECT * INTO retval FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';


    IF retval.code IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
    END IF;

    RETURN retval;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_record_type( rid BIGINT ) RETURNS config.marc21_rec_type_map AS $func$
    SELECT * FROM vandelay.marc21_record_type( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field( marc TEXT, ff TEXT ) RETURNS TEXT AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
            val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
            RETURN val;
        END LOOP;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        RETURN val;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field( rid BIGINT, ff TEXT ) RETURNS TEXT AS $func$
    SELECT * FROM vandelay.marc21_extract_fixed_field( (SELECT marc FROM biblio.record_entry WHERE id = $1), $2 );
$func$ LANGUAGE SQL;

CREATE TYPE biblio.record_ff_map AS (record BIGINT, ff_name TEXT, ff_value TEXT);
CREATE OR REPLACE FUNCTION vandelay.marc21_extract_all_fixed_fields( marc TEXT ) RETURNS SETOF biblio.record_ff_map AS $func$
DECLARE
    tag_data    TEXT;
    rtype       TEXT;
    ff_pos      RECORD;
    output      biblio.record_ff_map%ROWTYPE;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;

    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE rec_type = rtype ORDER BY tag DESC LOOP
        output.ff_name  := ff_pos.fixed_field;
        output.ff_value := NULL;

        FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(tag) || '"]/text()', marc ) ) x(value) LOOP
            output.ff_value := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
            IF output.ff_value IS NULL THEN output.ff_value := REPEAT( ff_pos.default_val, ff_pos.length ); END IF;
            RETURN NEXT output;
            output.ff_value := NULL;
        END LOOP;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_all_fixed_fields( rid BIGINT ) RETURNS SETOF biblio.record_ff_map AS $func$
    SELECT $1 AS record, ff_name, ff_value FROM vandelay.marc21_extract_all_fixed_fields( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_physical_characteristics( marc TEXT) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
DECLARE
    rowid   INT := 0;
    _007    TEXT;
    ptype   config.marc21_physical_characteristic_type_map%ROWTYPE;
    psf     config.marc21_physical_characteristic_subfield_map%ROWTYPE;
    pval    config.marc21_physical_characteristic_value_map%ROWTYPE;
    retval  biblio.marc21_physical_characteristics%ROWTYPE;
BEGIN

    _007 := oils_xpath_string( '//*[@tag="007"]', marc );

    IF _007 IS NOT NULL AND _007 <> '' THEN
        SELECT * INTO ptype FROM config.marc21_physical_characteristic_type_map WHERE ptype_key = SUBSTRING( _007, 1, 1 );

        IF ptype.ptype_key IS NOT NULL THEN
            FOR psf IN SELECT * FROM config.marc21_physical_characteristic_subfield_map WHERE ptype_key = ptype.ptype_key LOOP
                SELECT * INTO pval FROM config.marc21_physical_characteristic_value_map WHERE ptype_subfield = psf.id AND value = SUBSTRING( _007, psf.start_pos + 1, psf.length );

                IF pval.id IS NOT NULL THEN
                    rowid := rowid + 1;
                    retval.id := rowid;
                    retval.ptype := ptype.ptype_key;
                    retval.subfield := psf.id;
                    retval.value := pval.id;
                    RETURN NEXT retval;
                END IF;

            END LOOP;
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_physical_characteristics( rid BIGINT ) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
    SELECT id, $1 AS record, ptype, subfield, value FROM vandelay.marc21_physical_characteristics( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM metabib.record_attr WHERE id = NEW.id; -- Kill the attrs hash, useless on deleted records
        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;

                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  value::TEXT INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id)
                      WHERE subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( attr_value ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;

                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = attrs || new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION metabib.reingest_metabib_rec_descriptor( bib_id BIGINT );

CREATE OR REPLACE FUNCTION public.approximate_date( TEXT, TEXT ) RETURNS TEXT AS $func$
        SELECT REGEXP_REPLACE( $1, E'\\D', $2, 'g' );
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_low_date( TEXT ) RETURNS TEXT AS $func$
        SELECT approximate_date( $1, '0');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_high_date( TEXT ) RETURNS TEXT AS $func$
        SELECT approximate_date( $1, '9');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.integer_or_null( TEXT ) RETURNS TEXT AS $func$
        SELECT CASE WHEN $1 ~ E'^\\d+$' THEN $1 ELSE NULL END
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.content_or_null( TEXT ) RETURNS TEXT AS $func$
        SELECT CASE WHEN $1 ~ E'^\\s*$' THEN NULL ELSE $1 END
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.force_to_isbn13( TEXT ) RETURNS TEXT AS $func$
    use Business::ISBN;
    use strict;
    use warnings;

    # Find the first ISBN, force it to ISBN13 and return it

    my $input = shift;

    foreach my $word (split(/\s/, $input)) {
        my $isbn = Business::ISBN->new($word);

        # First check the checksum; if it is not valid, fix it and add the original
        # bad-checksum ISBN to the output
        if ($isbn && $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM) {
            $isbn->fix_checksum();
        }

        # If we now have a valid ISBN, force it to ISBN13 and return it
        return $isbn->as_isbn13->isbn if ($isbn && $isbn->is_valid());
    }
    return undef;
$func$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION public.force_to_isbn13(TEXT) IS $$
/*
 * Copyright (C) 2011 Equinox Software
 * Mike Rylander <mrylander@gmail.com>
 *
 * Inspired by translate_isbn1013
 *
 * The force_to_isbn13 function takes an input ISBN and returns the ISBN13
 * version without hypens and with a repaired checksum if the checksum was bad
 */
$$;

COMMIT;

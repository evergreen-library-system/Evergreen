BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0216');

DROP INDEX metabib.metabib_title_field_entry_value_idx;
DROP INDEX metabib.metabib_author_field_entry_value_idx;
DROP INDEX metabib.metabib_subject_field_entry_value_idx;
DROP INDEX metabib.metabib_keyword_field_entry_value_idx;
DROP INDEX metabib.metabib_series_field_entry_value_idx;

CREATE INDEX metabib_title_field_entry_value_idx ON metabib.title_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_author_field_entry_value_idx ON metabib.author_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_subject_field_entry_value_idx ON metabib.subject_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_keyword_field_entry_value_idx ON metabib.keyword_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_series_field_entry_value_idx ON metabib.series_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;

INSERT INTO config.internal_flag (name) VALUES ('ingest.reingest.skip_located_uri');

CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE 
        normalizer      RECORD;
        value           TEXT := '';
BEGIN
        IF NEW.index_vector = ''::tsvector THEN
            RETURN NEW;
        END IF;

        value := NEW.value;

        IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
                FOR normalizer IN
                        SELECT  n.func AS func,
                                n.param_count AS param_count,
                                m.params AS params
                          FROM  config.index_normalizer n
                                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
                          WHERE field = NEW.field
                          ORDER BY m.pos
                LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                                        quote_literal( value ) ||
                                        CASE
                                                WHEN normalizer.param_count > 0 THEN ',' || BTRIM(normalizer.params,'[]')
                                                ELSE ''
                                        END ||
                                ')' INTO value;

                END LOOP;
        END IF;

        IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT > 8.2 THEN
                NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, value);
        ELSE
                NEW.index_vector = to_tsvector(TG_ARGV[0], value);
        END IF;

        RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    ind_data        metabib.field_entry_template%ROWTYPE;
    old_mr          INT;
    tmp_mr          metabib.metarecord%ROWTYPE;
    source_count    INT;
    deleted_mrs     INT[];
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;

    ind_vector      TSVECTOR;
BEGIN

    IF NEW.deleted IS TRUE THEN
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;

        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage

    END IF;

    IF TG_OP = 'UPDATE' THEN -- Clean out the cruft
        DELETE FROM metabib.title_field_entry WHERE source = NEW.id;
        DELETE FROM metabib.author_field_entry WHERE source = NEW.id;
        DELETE FROM metabib.subject_field_entry WHERE source = NEW.id;
        DELETE FROM metabib.keyword_field_entry WHERE source = NEW.id;
        DELETE FROM metabib.series_field_entry WHERE source = NEW.id;
        DELETE FROM metabib.full_rec WHERE record = NEW.id;
        DELETE FROM metabib.rec_descriptor WHERE record = NEW.id;

    END IF;

    -- Shove the flattened MARC in
    INSERT INTO metabib.full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM biblio.flatten_marc( NEW.id );

    -- And now the indexing data
    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( NEW.id ) LOOP
        IF ind_data.field < 0 THEN
            ind_vector = '';
            ind_data.field = -1 * ind_data.field;
        ELSE
            ind_vector = NULL;
        END IF;

        IF ind_data.field_class = 'title' THEN
            INSERT INTO metabib.title_field_entry (field, source, value, index_vector)
                VALUES (ind_data.field, ind_data.source, ind_data.value, ind_vector);
        ELSIF ind_data.field_class = 'author' THEN
            INSERT INTO metabib.author_field_entry (field, source, value, index_vector)
                VALUES (ind_data.field, ind_data.source, ind_data.value, ind_vector);
        ELSIF ind_data.field_class = 'subject' THEN
            INSERT INTO metabib.subject_field_entry (field, source, value, index_vector)
                VALUES (ind_data.field, ind_data.source, ind_data.value, ind_vector);
        ELSIF ind_data.field_class = 'keyword' THEN
            INSERT INTO metabib.keyword_field_entry (field, source, value, index_vector)
                VALUES (ind_data.field, ind_data.source, ind_data.value, ind_vector);
        ELSIF ind_data.field_class = 'series' THEN
            INSERT INTO metabib.series_field_entry (field, source, value, index_vector)
                VALUES (ind_data.field, ind_data.source, ind_data.value, ind_vector);
        END IF;
    END LOOP;

    -- Then, the rec_descriptor
    INSERT INTO metabib.rec_descriptor (record, item_type, item_form, bib_level, control_type, enc_level, audience, lit_form, type_mat, cat_form, pub_status, item_lang, vr_format, date1, date2)
        SELECT  NEW.id,
                biblio.marc21_extract_fixed_field( NEW.id, 'Type' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'Form' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'BLvl' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'Ctrl' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'ELvl' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'Audn' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'LitF' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'TMat' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'Desc' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'DtSt' ),
                biblio.marc21_extract_fixed_field( NEW.id, 'Lang' ),
                (   SELECT  v.value
                      FROM  biblio.marc21_physical_characteristics( NEW.id) p
                            JOIN config.marc21_physical_characteristic_subfield_map s ON (s.id = p.subfield)
                            JOIN config.marc21_physical_characteristic_value_map v ON (v.id = p.value)
                      WHERE p.ptype = 'v' AND s.subfield = 'e'    ),
                biblio.marc21_extract_fixed_field( NEW.id, 'Date1'),
                biblio.marc21_extract_fixed_field( NEW.id, 'Date2');

    -- On to URIs ...
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.skip_located_uri' AND enabled;

    IF NOT FOUND OR TG_OP = 'INSERT' THEN
        uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',NEW.marc);
        IF ARRAY_UPPER(uris,1) > 0 THEN
            FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
                -- First we pull infot out of the 856
                uri_xml     := uris[i];
    
                uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
                CONTINUE WHEN uri_href IS NULL;
    
                uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()|//*[@code="u"]/text()',uri_xml))[1];
                CONTINUE WHEN uri_label IS NULL;
    
                uri_owner   := (oils_xpath('//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',uri_xml))[1];
                CONTINUE WHEN uri_owner IS NULL;
        
                uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];
    
                uri_owner := REGEXP_REPLACE(uri_owner, $re$^.*?\((\w+)\).*$$re$, E'\\1');
        
                SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
                CONTINUE WHEN NOT FOUND;
        
                -- now we look for a matching uri
                SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                IF NOT FOUND THEN -- create one
                    INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                    SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                END IF;
        
                -- we need a call number to link through
                SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = NEW.id AND label = '##URI##' AND NOT deleted;
                IF NOT FOUND THEN
                    INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                        VALUES (uri_owner_id, NEW.id, 'now', 'now', NEW.editor, NEW.editor, '##URI##');
                    SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = NEW.id AND label = '##URI##' AND NOT deleted;
                END IF;
        
                -- now, link them if they're not already
                SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                IF NOT FOUND THEN
                    INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
                END IF;
        
            END LOOP;
        END IF;
    END IF;

    -- And, finally, metarecord mapping!

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;

    IF NOT FOUND OR TG_OP = 'UPDATE' THEN
        FOR tmp_mr IN SELECT  m.* FROM  metabib.metarecord m JOIN metabib.metarecord_source_map s ON (s.metarecord = m.id) WHERE s.source = NEW.id LOOP
    
            IF old_mr IS NULL AND NEW.fingerprint = tmp_mr.fingerprint THEN -- Find the first fingerprint-matching
                old_mr := tmp_mr.id;
            ELSE
                SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id;
                IF source_count = 0 THEN -- No other records
                    deleted_mrs := ARRAY_APPEND(deleted_mrs, tmp_mr.id);
                    DELETE FROM metabib.metarecord WHERE id = tmp_mr.id;
                END IF;
            END IF;
    
        END LOOP;
    
        IF old_mr IS NULL THEN -- we found no suitable, preexisting MR based on old source maps
            SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = NEW.fingerprint; -- is there one for our current fingerprint?
            IF old_mr IS NULL THEN -- nope, create one and grab its id
                INSERT INTO metabib.metarecord ( fingerprint, master_record ) VALUES ( NEW.fingerprint, NEW.id );
                SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = NEW.fingerprint;
            ELSE -- indeed there is. update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = NEW.fingerprint ORDER BY quality DESC LIMIT 1)
                  WHERE id = old_mr;
            END IF;
        ELSE -- there was one we already attached to, update its mods cache and master_record
            UPDATE  metabib.metarecord
              SET   mods = NULL,
                    master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = NEW.fingerprint ORDER BY quality DESC LIMIT 1)
              WHERE id = old_mr;
        END IF;
    
        INSERT INTO metabib.metarecord_source_map (metarecord, source) VALUES (old_mr, NEW.id); -- new source mapping
    
        UPDATE action.hold_request SET target = old_mr WHERE target IN ( SELECT explode_array(deleted_mrs) ) AND hold_type = 'M'; -- if we had to delete any MRs above, make sure their holds are moved
    END IF;
 
    RETURN NEW;

END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

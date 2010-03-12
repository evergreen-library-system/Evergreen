BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0195'); -- miker

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
    match_attr      vandelay.bib_attr_definition%ROWTYPE;
BEGIN

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO match_count FROM vandelay.bib_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
        RETURN FALSE;
    END IF;

    SELECT  d.* INTO match_attr
      FROM  vandelay.bib_attr_definition d
            JOIN vandelay.queued_bib_record_attr a ON (a.field = d.id)
            JOIN vandelay.bib_match m ON (m.matched_attr = a.id)
      WHERE m.queued_record = import_id;

    IF NOT (match_attr.xpath ~ '@tag="901"' AND match_attr.xpath ~ '@code="c"') THEN
        -- RAISE NOTICE 'not a 901c match: %', match_attr.xpath;
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.bib_match m
      WHERE m.queued_record = import_id
      LIMIT 1;

    IF eg_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.match_bib_record ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr        RECORD;
    attr_def    RECORD;
    eg_rec      RECORD;
    id_value    TEXT;
    exact_id    BIGINT;
BEGIN

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT * INTO attr_def FROM vandelay.bib_attr_definition WHERE xpath = '//*[@tag="901"]/*[@code="c"]' ORDER BY id LIMIT 1;

    IF attr_def IS NOT NULL AND attr_def.id IS NOT NULL THEN
        id_value := extract_marc_field('vandelay.queued_bib_record', NEW.id, attr_def.xpath, attr_def.remove);

        IF id_value IS NOT NULL AND id_value <> '' AND id_value ~ $r$^\d+$$r$ THEN
            SELECT id INTO exact_id FROM biblio.record_entry WHERE id = id_value::BIGINT AND NOT deleted;
            SELECT * INTO attr FROM vandelay.queued_bib_record_attr WHERE record = NEW.id and field = attr_def.id LIMIT 1;
            IF exact_id IS NOT NULL THEN
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, exact_id);
            END IF;
        END IF;
    END IF;

    IF exact_id IS NULL THEN
        FOR attr IN SELECT a.* FROM vandelay.queued_bib_record_attr a JOIN vandelay.bib_attr_definition d ON (d.id = a.field) WHERE record = NEW.id AND d.ident IS TRUE LOOP

            -- All numbers? check for an id match
            IF (attr.attr_value ~ $r$^\d+$$r$) THEN
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE id = attr.attr_value::BIGINT AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- Looks like an ISBN? check for an isbn match
            IF (attr.attr_value ~* $r$^[0-9x]+$$r$ AND character_length(attr.attr_value) IN (10,13)) THEN
                FOR eg_rec IN EXECUTE $$SELECT * FROM metabib.full_rec fr WHERE fr.value LIKE LOWER('$$ || attr.attr_value || $$%') AND fr.tag = '020' AND fr.subfield = 'a'$$ LOOP
                    PERFORM id FROM biblio.record_entry WHERE id = eg_rec.record AND deleted IS FALSE;
                    IF FOUND THEN
                        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('isbn', attr.id, NEW.id, eg_rec.record);
                    END IF;
                END LOOP;

                -- subcheck for isbn-as-tcn
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = 'i' || attr.attr_value AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- check for an OCLC tcn_value match
            IF (attr.attr_value ~ $r$^o\d+$$r$) THEN
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = regexp_replace(attr.attr_value,'^o','ocm') AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- check for a direct tcn_value match
            FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = attr.attr_value AND deleted IS FALSE LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
            END LOOP;

            -- check for a direct item barcode match
            FOR eg_rec IN
                    SELECT  DISTINCT b.*
                      FROM  biblio.record_entry b
                            JOIN asset.call_number cn ON (cn.record = b.id)
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cp.barcode = attr.attr_value AND cp.deleted IS FALSE
            LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
            END LOOP;

        END LOOP;
    END IF;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;


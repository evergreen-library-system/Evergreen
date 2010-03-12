
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0192'); -- miker

CREATE OR REPLACE FUNCTION vandelay.compile_profile ( incoming_xml TEXT ) RETURNS vandelay.compile_profile AS $_$
DECLARE
    output              vandelay.compile_profile%ROWTYPE;
    profile             vandelay.merge_profile%ROWTYPE;
    profile_tmpl        TEXT;
    profile_tmpl_owner  TEXT;
    add_rule            TEXT := '';
    strip_rule          TEXT := '';
    replace_rule        TEXT := '';
    preserve_rule       TEXT := '';

BEGIN

    profile_tmpl := (oils_xpath('//*[@tag="905"]/*[@code="t"]/text()',incoming_xml))[1];
    profile_tmpl_owner := (oils_xpath('//*[@tag="905"]/*[@code="o"]/text()',incoming_xml))[1];

    IF profile_tmpl IS NOT NULL AND profile_tmpl <> '' AND profile_tmpl_owner IS NOT NULL AND profile_tmpl_owner <> '' THEN
        SELECT  p.* INTO profile
          FROM  vandelay.merge_profile p
                JOIN actor.org_unit u ON (u.id = p.owner)
          WHERE p.name = profile_tmpl
                AND u.shortname = profile_tmpl_owner;

        IF profile.id IS NOT NULL THEN
            add_rule := COALESCE(profile.add_spec,'');
            strip_rule := COALESCE(profile.strip_spec,'');
            replace_rule := COALESCE(profile.replace_spec,'');
            preserve_rule := COALESCE(profile.preserve_spec,'');
        END IF;
    END IF;

    add_rule := add_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="a"]/text()',incoming_xml),''),'');
    strip_rule := strip_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="d"]/text()',incoming_xml),''),'');
    replace_rule := replace_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="r"]/text()',incoming_xml),''),'');
    preserve_rule := preserve_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="p"]/text()',incoming_xml),''),'');

    output.add_rule := BTRIM(add_rule,',');
    output.replace_rule := BTRIM(replace_rule,',');
    output.strip_rule := BTRIM(strip_rule,',');
    output.preserve_rule := BTRIM(preserve_rule,',');

    RETURN output;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  biblio.record_entry b
            JOIN vandelay.bib_match m ON (m.eg_record = b.id AND m.queued_record = import_id)
      LIMIT 1;

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := BTRIM( dyn_profile.add_rule || ',' || COALESCE(merge_profile.add_spec,''), ',');
            dyn_profile.strip_rule := BTRIM( dyn_profile.strip_rule || ',' || COALESCE(merge_profile.strip_spec,''), ',');
            dyn_profile.replace_rule := BTRIM( dyn_profile.replace_rule || ',' || COALESCE(merge_profile.replace_spec,''), ',');
            dyn_profile.preserve_rule := BTRIM( dyn_profile.preserve_rule || ',' || COALESCE(merge_profile.preserve_spec,''), ',');
        END IF;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF FOUND THEN
        UPDATE  vandelay.queued_bib_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;
        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of biblio.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
BEGIN
    SELECT COUNT(*) INTO match_count FROM vandelay.bib_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
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
    eg_rec      RECORD;
    id_value    TEXT;
    exact_id    BIGINT;
BEGIN

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT * INTO attr FROM vandelay.bib_attr_definition WHERE xpath = '//*[@tag="901"]/*[@code="c"]' ORDER BY id LIMIT 1;

    IF attr IS NOT NULL AND attr.id IS NOT NULL THEN
        id_value := extract_marc_field('vandelay.queued_bib_record', NEW.id, attr.xpath, attr.remove);

        IF id_value IS NOT NULL AND id_value <> '' AND id_value ~ $r$^\d+$$r$ THEN
            SELECT id INTO exact_id FROM biblio.record_entry WHERE id = id_value::BIGINT AND NOT deleted;
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


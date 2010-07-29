BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0354'); -- berick

CREATE OR REPLACE FUNCTION vandelay.template_overlay_bib_record ( v_marc TEXT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  biblio.record_entry b
      WHERE b.id = eg_id
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for template or bib record';
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

    IF NOT FOUND THEN
        -- RAISE NOTICE 'update of biblio.record_entry failed';
        RETURN FALSE;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

COMMIT;

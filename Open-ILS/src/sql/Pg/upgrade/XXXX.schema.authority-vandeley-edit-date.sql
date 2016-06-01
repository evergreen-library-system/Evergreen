BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.overlay_authority_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
    update_fields   TEXT[];
    update_query    TEXT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  authority.record_entry b
            JOIN vandelay.authority_match m ON (m.eg_record = b.id AND m.queued_record = import_id)
      LIMIT 1;

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.authority_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or authority record';
        RETURN FALSE;
    END IF;

    -- Extract the editor string before any modification to the vandelay
    -- MARC occur.
    editor_string := 
        (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

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

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        --Since we have nothing to do, just return a NOOP "we did it"
        RETURN TRUE;
    ELSIF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  authority.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF NOT FOUND THEN 
        -- Import/merge failed.  Nothing left to do.
        RETURN FALSE;
    END IF;

    -- Authority record successfully merged / imported.

    -- Update the vandelay record to show the successful import.
    UPDATE  vandelay.queued_authority_record
      SET   imported_as = eg_id,
            import_time = NOW()
      WHERE id = import_id;

    -- If an editor value can be found, update the authority record
    -- editor and edit_date values.
    IF editor_string IS NOT NULL AND editor_string <> '' THEN

        -- Vandelay.pm sets the value to 'usrname' when needed.  
        SELECT id INTO editor_id 
            FROM actor.usr WHERE usrname = editor_string;

        IF editor_id IS NULL THEN
            SELECT usr INTO editor_id 
                FROM actor.card WHERE barcode = editor_string;
        END IF;

        IF editor_id IS NOT NULL THEN
            --only update the edit date if we have a valid editor
            update_fields := ARRAY_APPEND(update_fields, 
                'editor = ' || editor_id || ', edit_date = NOW()');
        END IF;
    END IF;

    IF ARRAY_LENGTH(update_fields, 1) > 0 THEN
        update_query := 'UPDATE authority.record_entry SET ' || 
            ARRAY_TO_STRING(update_fields, ',') || 
            ' WHERE id = ' || eg_id || ';';
        --RAISE NOTICE 'query: %', update_query;
        EXECUTE update_query;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;


COMMIT;


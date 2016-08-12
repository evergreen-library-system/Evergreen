BEGIN;

SELECT evergreen.upgrade_deps_block_check('0989', :eg_version); -- berick/miker/gmcharlt

CREATE OR REPLACE FUNCTION vandelay.overlay_authority_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    new_editor      INT;
    new_edit_date   TIMESTAMPTZ;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc_row     authority.record_entry%ROWTYPE;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
    update_query    TEXT;
BEGIN

    SELECT  * INTO eg_marc_row
      FROM  authority.record_entry b
            JOIN vandelay.authority_match m ON (m.eg_record = b.id AND m.queued_record = import_id)
      LIMIT 1;

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.authority_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    eg_marc := eg_marc_row.marc;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or authority record';
        RETURN FALSE;
    END IF;

    -- Extract the editor string before any modification to the vandelay
    -- MARC occur.
    editor_string := 
        (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

    -- If an editor value can be found, update the authority record
    -- editor and edit_date values.
    IF editor_string IS NOT NULL AND editor_string <> '' THEN

        -- Vandelay.pm sets the value to 'usrname' when needed.  
        SELECT id INTO new_editor
            FROM actor.usr WHERE usrname = editor_string;

        IF new_editor IS NULL THEN
            SELECT usr INTO new_editor
                FROM actor.card WHERE barcode = editor_string;
        END IF;

        IF new_editor IS NOT NULL THEN
            new_edit_date := NOW();
        ELSE -- No valid editor, use current values
            new_editor = eg_marc_row.editor;
            new_edit_date = eg_marc_row.edit_date;
        END IF;
    ELSE
        new_editor = eg_marc_row.editor;
        new_edit_date = eg_marc_row.edit_date;
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
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule ),
            editor = new_editor,
            edit_date = new_edit_date
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

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;


COMMIT;


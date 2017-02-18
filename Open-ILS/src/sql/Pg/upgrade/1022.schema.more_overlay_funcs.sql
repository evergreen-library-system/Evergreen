BEGIN;

SELECT evergreen.upgrade_deps_block_check('1022', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml_using_profile ( incoming_marc TEXT, existing_marc TEXT, merge_profile_id BIGINT ) RETURNS TEXT AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    target_marc     TEXT;
    source_marc     TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    IF existing_marc IS NULL OR incoming_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for source or target records';
        RETURN NULL;
    END IF;

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := COALESCE(merge_profile.add_spec,'');
            dyn_profile.strip_rule := COALESCE(merge_profile.strip_spec,'');
            dyn_profile.replace_rule := COALESCE(merge_profile.replace_spec,'');
            dyn_profile.preserve_rule := COALESCE(merge_profile.preserve_spec,'');
        ELSE
            -- RAISE NOTICE 'merge profile not found';
            RETURN NULL;
        END IF;
    ELSE
        -- RAISE NOTICE 'no merge profile specified';
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        -- Since we have nothing to do, just return a target record as is
        RETURN existing_marc;
    ELSIF dyn_profile.preserve_rule <> '' THEN
        source_marc = existing_marc;
        target_marc = incoming_marc;
        replace_rule = dyn_profile.preserve_rule;
    ELSE
        source_marc = incoming_marc;
        target_marc = existing_marc;
        replace_rule = dyn_profile.replace_rule;
    END IF;

    RETURN vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule );

END;
$$ LANGUAGE PLPGSQL;

COMMIT;

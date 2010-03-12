BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0193'); -- miker

CREATE OR REPLACE FUNCTION vandelay.overlay_authority_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
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

    UPDATE  authority.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF FOUND THEN
        UPDATE  vandelay.queued_authority_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;
        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of authority.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
BEGIN
    SELECT COUNT(*) INTO match_count FROM vandelay.authority_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.authority_match m
      WHERE m.queued_record = import_id
      LIMIT 1;

    IF eg_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_authority_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_queue ( queue_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_authority_record%ROWTYPE;
    success         BOOL;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_authority_record WHERE queue = queue_id AND import_time IS NULL LOOP
        success := vandelay.auto_overlay_authority_record( queued_record.id, merge_profile_id );

        IF success THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;
    
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_queue ( queue_id BIGINT ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM vandelay.auto_overlay_authority_queue( $1, NULL );
$$ LANGUAGE SQL;


COMMIT;


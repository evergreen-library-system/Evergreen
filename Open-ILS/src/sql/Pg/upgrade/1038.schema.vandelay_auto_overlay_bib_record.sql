BEGIN;

SELECT evergreen.upgrade_deps_block_check('1038', :eg_version); 

-- This function was replaced back in 2011, but never made it
-- into an upgrade script.  Here it is, nearly 6 years later.

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
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

    -- Check that the one match is on the first 901c
    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.queued_bib_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id)
      WHERE q.id = import_id
            AND m.eg_record = oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]',marc)::BIGINT;

    IF NOT FOUND THEN
        -- RAISE NOTICE 'not a 901c match';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

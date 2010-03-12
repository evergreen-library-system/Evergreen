BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0194'); -- miker

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
    match_attr      vandelay.bib_attr_definition%ROWTYPE;
BEGIN
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
        -- RAISE NOTICE 'not a 901c match';
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

COMMIT;

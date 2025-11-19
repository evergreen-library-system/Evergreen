--Upgrade Script for 3.16.0 to 3.16.1
\set eg_version '''3.16.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.16.1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1503', :eg_version);

CREATE OR REPLACE FUNCTION asset.record_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
DECLARE
    ous INT[] := (SELECT array_agg(id) FROM actor.org_unit_descendants(COALESCE(ou, (SELECT id FROM evergreen.org_top()))));
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
        WHERE
            acn.record = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acpl.deleted = false
            AND acp.circ_lib = ANY(ous)
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1504', :eg_version); -- phasefx

-- A/T seed data
INSERT into action_trigger.hook (key, core_type, description) VALUES
( 'au.erenewal', 'au', 'A patron has been renewed via Erenewal');

COMMIT;

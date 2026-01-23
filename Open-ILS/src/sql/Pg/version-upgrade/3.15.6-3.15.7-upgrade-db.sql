--Upgrade Script for 3.15.6 to 3.15.7
\set eg_version '''3.15.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.15.7', :eg_version);

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

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();

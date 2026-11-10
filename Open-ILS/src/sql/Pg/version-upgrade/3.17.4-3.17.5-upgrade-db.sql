--Upgrade Script for 3.17.4 to 3.17.5
\set eg_version '''3.17.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.17.5', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1526', :eg_version);

-- Fix broken JOIN in the 'ateo' case of evergreen.hint_opt_in_check.
-- The original code joined action_trigger.event_output eo ON (eo.event = e.id),
-- but action_trigger.event_output has no 'event' column. The relationship is
-- reversed: action_trigger.event has template_output, error_output, and
-- async_output columns that reference event_output.id.

CREATE OR REPLACE FUNCTION evergreen.hint_opt_in_check(
    hint_val    TEXT,
    pkey_val    BIGINT, -- pkey value of the hinted row
    staff_id    INT,
    permlist    TEXT[] DEFAULT '{}'::TEXT[] -- if passed, staff must ADDITIONALLY possess at least one of these permissions at an opted-in location
) RETURNS BOOLEAN AS $f$
BEGIN
    CASE hint_val
        WHEN 'aua' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_address WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'auact' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_activity WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'aus' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_setting WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'actscecm' THEN
            RETURN evergreen.direct_opt_in_check((SELECT target_usr FROM actor.stat_cat_entry_usr_map WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'ateo' THEN
            RETURN evergreen.direct_opt_in_check(
                (SELECT e.context_user FROM action_trigger.event e JOIN action_trigger.event_output eo ON (eo.id = e.template_output OR eo.id = e.error_output OR eo.id = e.async_output) WHERE eo.id = pkey_val LIMIT 1),
                staff_id,
                permlist
            );
        ELSE
            RETURN FALSE;
    END CASE;
END;
$f$ STABLE LANGUAGE PLPGSQL;

SELECT evergreen.upgrade_deps_block_check('1527', :eg_version);

UPDATE config.org_unit_setting_type
SET grp='holds'
WHERE
name='circ.holds.calculated_age_proximity'
and grp='circ'
;

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();

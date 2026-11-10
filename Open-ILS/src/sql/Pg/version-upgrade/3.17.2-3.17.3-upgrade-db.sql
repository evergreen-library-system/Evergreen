--Upgrade Script for 3.17.2 to 3.17.3
\set eg_version '''3.17.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.17.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1525', :eg_version);

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

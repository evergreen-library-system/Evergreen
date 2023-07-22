--Upgrade Script for 3.11.0 to 3.11.1
\set eg_version '''3.11.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1379', :eg_version);

-- this intentionally does nothing other than inserting the
-- database revision stamp; the only substantive use of 1379
-- is in rel_3_10, but it's important to ensure that anybody
-- applying the individual DB updates doesn't accidentally
-- apply the 1379 change to a 3.11 or later system


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();

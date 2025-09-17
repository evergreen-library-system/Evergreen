--Upgrade Script for 3.14.9 to 3.14.10
\set eg_version '''3.14.10'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.14.10', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1485', :eg_version);

UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'auth.opac_timeout',
            'Number of seconds of inactivity before the patron is logged out of the OPAC. The minimum value that can be entered is 240 seconds. At the 180 second mark a countdown will appear and patrons can choose to end the session, continue the session, or allow it to time out.',
            'cwst', 'description') 
        WHERE name = 'auth.opac_timeout';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();

BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'auth.opac_timeout',
            'Number of seconds of inactivity before the patron is logged out of the OPAC. The minimum value that can be entered is 240 seconds. At the 180 second mark a countdown will appear and patrons can choose to end the session, continue the session, or allow it to time out.',
            'cwst', 'description') 
        WHERE name = 'auth.opac_timeout';

COMMIT;

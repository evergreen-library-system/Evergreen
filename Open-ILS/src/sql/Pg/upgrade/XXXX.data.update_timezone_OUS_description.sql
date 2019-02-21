BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.org_unit_setting_type
    SET description =
'Define the time zone in which a library physically resides. Examples: America/Toronto, ' ||
'America/Chicago, America/Denver, America/Vancouver, Europe/Prague. See Wikipedia for a ' ||
'<a href="https://en.wikipedia.org/wiki/List_of_tz_database_time_zones" target="_blank">complete list</a> ' ||
'(Note: Only use "canonical" timezones).'
    WHERE name = 'lib.timezone';

COMMIT;



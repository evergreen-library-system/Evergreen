--Upgrade Script for 3.2.6 to 3.2.7
\set eg_version '''3.2.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.2.7', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1164', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.patron.group_members', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.circ.patron.group_members',
    'Grid Config: circ.patron.group_members',
    'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1165', :eg_version);

INSERT INTO config.org_unit_setting_type (name,label,grp,description,datatype)
VALUES ('ui.patron.edit.au.dob.example',oils_i18n_gettext('ui.patron.edit.au.dob.example',
        'Example dob field on patron registration', 'coust', 'label'),'gui',
    oils_i18n_gettext('ui.patron.edit.au.dob.example',
        'The Example for validation on the dob field in patron registration.', 'coust', 'description'),
    'string');


SELECT evergreen.upgrade_deps_block_check('1166', :eg_version);

UPDATE config.org_unit_setting_type
    SET description =
'Define the time zone in which a library physically resides. Examples: America/Toronto, ' ||
'America/Chicago, America/Los_Angeles, America/Vancouver, Europe/Prague. See Wikipedia for a ' ||
'<a href="https://en.wikipedia.org/wiki/List_of_tz_database_time_zones" target="_blank">complete list</a> ' ||
'(Note: Only use "canonical" timezones).'
WHERE name = 'lib.timezone'
AND description = 'Define the time zone in which a library physically resides';




SELECT evergreen.upgrade_deps_block_check('1167', :eg_version);

INSERT INTO config.workstation_setting_type (name,label,grp,datatype) VALUES ('eg.circ.bills.annotatepayment','Bills: Annotate Payment', 'circ', 'bool');


COMMIT;

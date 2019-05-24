BEGIN;

SELECT evergreen.upgrade_deps_block_check('1165', :eg_version);

INSERT INTO config.org_unit_setting_type (name,label,grp,description,datatype)
VALUES ('ui.patron.edit.au.dob.example',oils_i18n_gettext('ui.patron.edit.au.dob.example',
        'Example dob field on patron registration', 'coust', 'label'),'gui',
    oils_i18n_gettext('ui.patron.edit.au.dob.example',
        'The Example for validation on the dob field in patron registration.', 'coust', 'description'),
    'string');

COMMIT;

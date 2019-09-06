BEGIN;

SELECT evergreen.upgrade_deps_block_check('1183', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'ui.patron.edit.au.ident_value.require', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.ident_value.require',
        'require ident_value field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.ident_value.require',
        'The ident_value field will be required on the patron registration screen.',
        'coust', 'description'),
    'bool', null);

COMMIT;


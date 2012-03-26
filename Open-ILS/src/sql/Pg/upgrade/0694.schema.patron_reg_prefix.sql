BEGIN;

SELECT evergreen.upgrade_deps_block_check('0694', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

( 'ui.patron.edit.au.prefix.require', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.prefix.require',
        'Require prefix field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.prefix.require',
        'The prefix field will be required on the patron registration screen.'
        'coust', 'description'),
    'bool', null)
	
,( 'ui.patron.edit.au.prefix.show', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.prefix.show',
        'Show prefix field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.prefix.show',
        'The prefix field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.'
        'coust', 'description'),
    'bool', null)

,( 'ui.patron.edit.au.prefix.suggest', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.prefix.suggest',
        'Suggest prefix field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.prefix.suggest',
        'The prefix field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.'
        'coust', 'description'),
    'bool', null)
;		

COMMIT;

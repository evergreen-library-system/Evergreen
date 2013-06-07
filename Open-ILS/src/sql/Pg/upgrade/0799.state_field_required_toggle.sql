BEGIN;

SELECT evergreen.upgrade_deps_block_check('0799', :eg_version);

-- allow state to be null
ALTER TABLE actor.usr_address ALTER COLUMN state DROP NOT NULL;

-- create new YAOUS
INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.state.require',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.state.require',
            'Require State field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.state.require',
            'The State field will be required on the patron registration screen.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.state.show',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.state.show',
            'Show State field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.state.show',
            'The State field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.',
            'coust',
            'description'
        ),
        'bool'
    );	

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.state.suggest',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.state.suggest',
            'Suggest State field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.state.suggest',
            'The State field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.',
            'coust',
            'description'
        ),
        'bool'
    );		

COMMIT;

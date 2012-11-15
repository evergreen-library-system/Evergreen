BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- state can no longer be a "not null"
ALTER TABLE actor.usr_address ALTER COLUMN state DROP NOT NULL;

-- create new YAOUS
INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.state.require',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.state.require',
            'Require State on registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.state.require',
            'Require the State field to be filled when registering or editing a patron.',
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
            'Show State on registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.state.show',
            'Show the state field when registering or editing a patron.',
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
            'Suggest State on registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.state.suggest',
            'Suggest filling the state field when registering or editing a patron.',
            'coust',
            'description'
        ),
        'bool'
    );		

COMMIT;

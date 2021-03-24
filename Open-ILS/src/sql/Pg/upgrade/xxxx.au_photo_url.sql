BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.photo_url.require',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.require',
            'Require Photo URL field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.require',
            'The Photo URL field will be required on the patron registration screen.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.photo_url.show',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.show',
            'Show Photo URL field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.show',
            'The Photo URL field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.photo_url.suggest',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.suggest',
            'Suggest Photo URL field on patron registration',
            'coust',
            'label'
        ),

        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.suggest',
            'The Photo URL field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 632, 'UPDATE_USER_PHOTO_URL', oils_i18n_gettext( 632,
   'Update the user photo url field in patron registration and editor', 'ppl', 'description' ))
;

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Circulators' AND
                aout.name = 'System' AND
                perm.code = 'UPDATE_USER_PHOTO_URL'
;

COMMIT;

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0741', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    540,
    'ADMIN_TOOLBAR_FOR_ORG',
    oils_i18n_gettext(
        540,
        'Allows a user to create, edit, and delete custom toolbars for org units',
        'ppl',
        'description'
    )
), (
    541,
    'ADMIN_TOOLBAR_FOR_WORKSTATION',
    oils_i18n_gettext(
        541,
        'Allows a user to create, edit, and delete custom toolbars for workstations',
        'ppl',
        'description'
    )
), (
    542,
    'ADMIN_TOOLBAR_FOR_USER',
    oils_i18n_gettext(
        542,
        'Allows a user to create, edit, and delete custom toolbars for users',
        'ppl',
        'description'
    )
);

COMMIT;


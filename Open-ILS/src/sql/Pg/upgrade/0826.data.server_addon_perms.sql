BEGIN;

SELECT evergreen.upgrade_deps_block_check('0826', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    551,
    'ADMIN_SERVER_ADDON_FOR_WORKSTATION',
    oils_i18n_gettext(
        551,
        'Allows a user to specify which Server Add-ons get invoked at the current workstation',
        'ppl',
        'description'
    )
);

COMMIT;


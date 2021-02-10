BEGIN;

SELECT evergreen.upgrade_deps_block_check('1245', :eg_version);

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'auth.block_expired_staff_login',
    NULL,
    FALSE,
    oils_i18n_gettext(
        'auth.block_expired_staff_login',
        'Block the ability of expired user with the STAFF_LOGIN permission to log into Evergreen.',
        'cgf', 'label'
    )
);

COMMIT;

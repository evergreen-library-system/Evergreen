BEGIN;

SELECT evergreen.upgrade_deps_block_check('0944', :eg_version);

INSERT INTO permission.perm_list (id, code, description)
    VALUES (
        563,
        'ADJUST_BILLS',
        oils_i18n_gettext(
            563,
            'Allow a user to adjust a bill (generally to zero)',
            'ppl',
            'description'
        )
    );

COMMIT;

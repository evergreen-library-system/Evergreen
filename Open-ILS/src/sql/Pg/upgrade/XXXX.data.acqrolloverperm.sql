BEGIN;

INSERT INTO permission.perm_list ( id, code, description )
    VALUES (
        639,
        'ADMIN_FUND_ROLLOVER',
        oils_i18n_gettext(
            639,
            'Allow a user to perform fund propagation and rollover',
            'ppl',
            'description'
        )
    );

COMMIT;
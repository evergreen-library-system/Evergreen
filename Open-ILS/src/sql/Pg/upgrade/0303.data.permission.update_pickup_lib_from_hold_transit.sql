BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0303'); -- phasefx

INSERT INTO permission.perm_list (id, code, description) VALUES (
    391,
    'UPDATE_PICKUP_LIB_FROM_TRANSIT',
    oils_i18n_gettext(
        391,
        'Allow a user to change the pickup and transit destination for a captured hold item already in transit',
        'ppl',
        'description'
    )
);

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0634');

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 513, 'DEBUG_CLIENT', oils_i18n_gettext( 513,
    'Allows a user to use debug functions in the staff client', 'ppl', 'description' ));

COMMIT;

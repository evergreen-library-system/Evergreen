BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0634', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 513, 'DEBUG_CLIENT', oils_i18n_gettext( 513,
    'Allows a user to use debug functions in the staff client', 'ppl', 'description' ));

COMMIT;

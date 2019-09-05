BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 619, 'EDIT_SELF_IN_CLIENT', oils_i18n_gettext(619,
    'Allow a user to edit their own account in the staff client', 'ppl', 'description'))
;

COMMIT;

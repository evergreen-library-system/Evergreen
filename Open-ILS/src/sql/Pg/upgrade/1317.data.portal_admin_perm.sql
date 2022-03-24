BEGIN;

SELECT evergreen.upgrade_deps_block_check('1317', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 636, 'ADMIN_STAFF_PORTAL_PAGE', oils_i18n_gettext( 636,
   'Update the staff client portal page', 'ppl', 'description' ))
;

COMMIT;

BEGIN;

SELECT evergreen.upgrade_deps_block_check('1191', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
  619,
  'EDIT_SELF_IN_CLIENT',
  oils_i18n_gettext(619,
    'Allow a user to edit their own account in the staff client', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'EDIT_SELF_IN_CLIENT');

COMMIT;

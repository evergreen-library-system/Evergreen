BEGIN;

SELECT evergreen.upgrade_deps_block_check('1401', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
  648,
  'ADMIN_BIB_BUCKET',
  oils_i18n_gettext(648,
    'Administer bibliographic record buckets', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_BIB_BUCKET');
 
INSERT INTO permission.perm_list ( id, code, description )  SELECT DISTINCT
  649,
  'CREATE_BIB_BUCKET',
  oils_i18n_gettext(649,
    'Create bibliographic record buckets', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'CREATE_BIB_BUCKET');

COMMIT;
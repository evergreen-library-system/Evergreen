--Upgrade Script for 3.12.1 to 3.12.2
\set eg_version '''3.12.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.12.2', :eg_version);

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


SELECT evergreen.upgrade_deps_block_check('1402', :eg_version);

INSERT INTO config.org_unit_setting_type (
  name, grp, label, description, datatype
) VALUES (
  'cat.patron_view_discovery_layer_url',
  'cat',
  oils_i18n_gettext(
    'cat.patron_view_discovery_layer_url',
    'Patron view discovery layer URL',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'cat.patron_view_discovery_layer_url',
    'URL for displaying an item in the "patron view" discovery layer with a placeholder for the bib record ID: {eg_record_id}. For example: https://example.com/Record/{eg_record_id}',
    'coust',
    'description'
  ),
  'string'
);

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();

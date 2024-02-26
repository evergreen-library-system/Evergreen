--Upgrade Script for 3.11.3 to 3.11.4
\set eg_version '''3.11.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.4', :eg_version);

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

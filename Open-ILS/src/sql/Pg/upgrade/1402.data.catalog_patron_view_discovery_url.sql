BEGIN;

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

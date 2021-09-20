BEGIN;

SELECT evergreen.upgrade_deps_block_check('1286', :eg_version);

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'eg.staffcat.search_filters', 'gui',
  oils_i18n_gettext(
    'eg.staffcat.search_filters',
    'Staff Catalog Search Filters',
    'coust', 'label'),
  oils_i18n_gettext(
    'eg.staffcat.search_filters',
    'Array of advanced search filters to display, e.g. ["item_lang","audience","lit_form"]',
    'coust', 'description'),
  'array' );

COMMIT;




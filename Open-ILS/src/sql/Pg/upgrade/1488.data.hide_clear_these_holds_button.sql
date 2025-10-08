BEGIN;

SELECT evergreen.upgrade_deps_block_check('1488', :eg_version);

INSERT INTO config.org_unit_setting_type (
name, grp, label, description, datatype
) VALUES (
  'ui.hide_clear_these_holds_button',
  'gui',
  oils_i18n_gettext(
    'ui.hide_clear_these_holds_button',
    'Hide the Clear These Holds button',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'ui.hide_clear_these_holds_button',
    'Hide the Clear These Holds button from the Holds Shelf interface.',
    'coust',
    'description'
  ),
  'bool'
);

COMMIT;

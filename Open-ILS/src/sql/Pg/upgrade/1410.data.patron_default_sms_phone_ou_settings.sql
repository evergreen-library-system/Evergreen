BEGIN;

SELECT evergreen.upgrade_deps_block_check('1410', :eg_version);

INSERT INTO config.org_unit_setting_type (
  name, grp, label, description, datatype
) VALUES (
  'ui.patron.edit.aus.default_phone.regex',
  'gui',
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_phone.regex',
    'Regex for default_phone field on patron registration',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_phone.regex',
    'The Regular Expression for validation on the default_phone field in patron registration.',
    'coust',
    'description'
  ),
  'string'
), (
  'ui.patron.edit.aus.default_phone.example',
  'gui',
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_phone.example',
    'Example for default_phone field on patron registration',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_phone.example',
    'The Example for validation on the default_phone field in patron registration.',
    'coust',
    'description'
  ),
  'string'
), (
  'ui.patron.edit.aus.default_sms_notify.regex',
  'gui',
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_sms_notify.regex',
    'Regex for default_sms_notify field on patron registration',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_sms_notify.regex',
    'The Regular Expression for validation on the default_sms_notify field in patron registration.',
    'coust',
    'description'
  ),
  'string'
), (
  'ui.patron.edit.aus.default_sms_notify.example',
  'gui',
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_sms_notify.example',
    'Example for default_sms_notify field on patron registration',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'ui.patron.edit.aus.default_sms_notify.example',
    'The Example for validation on the default_sms_notify field in patron registration.',
    'coust',
    'description'
  ),
  'string'
);

COMMIT;

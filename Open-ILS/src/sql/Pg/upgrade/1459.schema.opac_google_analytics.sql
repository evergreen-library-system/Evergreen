BEGIN;

-- Move Google Analytics settings from config.tt2 to library settings

SELECT evergreen.upgrade_deps_block_check('1459', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.google_analytics_enable',
    'opac',
    oils_i18n_gettext('opac.google_analytics_enable',
    'Google Analytics: Enable',
    'coust', 'label'),
    oils_i18n_gettext('opac.alert_message_show',
    'Enable Google Analytics in the OPAC. Default is false.',
    'coust', 'description'),
    'bool'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.google_analytics_code',
    'opac',
    oils_i18n_gettext('opac.google_analytics_code',
    'Google Analytics: Code',
    'coust', 'label'),
    oils_i18n_gettext('opac.google_analytics_code',
    'Account code provided by Google. (Example: G-GVGQ11X12)',
    'coust', 'description'),
    'string'
);

COMMIT;
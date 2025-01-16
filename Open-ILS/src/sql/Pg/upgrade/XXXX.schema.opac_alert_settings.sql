BEGIN;

-- Move OPAC alert banner feature from config file to a library setting

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.org_unit_setting_type
         (name, grp, label, description, datatype)
VALUES (
         'opac.alert_banner_show',
         'opac',
         oils_i18n_gettext('opac.alert_banner_show',
         'OPAC Alert Banner: Display',
         'coust', 'label'),
         oils_i18n_gettext('opac.alert_message_show',
         'Show an alert banner in the OPAC. Default is false.',
         'coust', 'description'),
         'bool'
);

INSERT into config.org_unit_setting_type
         (name, grp, label, description, datatype)
VALUES (
         'opac.alert_banner_type',
         'opac',
         oils_i18n_gettext('opac.alert_banner_type',
         'OPAC Alert Banner: Type',
         'coust', 'label'),
         oils_i18n_gettext('opac.alert_message_type',
         'Determine the display of the banner. Options are: success, info, warning, danger.',
         'coust', 'description'),
         'string'
);

INSERT into config.org_unit_setting_type
         (name, grp, label, description, datatype)
VALUES (
         'opac.alert_banner_text',
         'opac',
         oils_i18n_gettext('opac.alert_banner_text',
         'OPAC Alert Banner: Text',
         'coust', 'label'),
         oils_i18n_gettext('opac.alert_message_text',
         'Text that will display in the alert banner.',
         'coust', 'description'),
         'string'
);

 COMMIT;
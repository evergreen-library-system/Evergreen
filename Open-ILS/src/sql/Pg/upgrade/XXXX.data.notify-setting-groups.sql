BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
    ('notify.sms',   oils_i18n_gettext('notify.sms',   'Text Notices',  'csg', 'label')),
    ('notify.email', oils_i18n_gettext('notify.email', 'Email Notices', 'csg', 'label')),
    ('notify.phone', oils_i18n_gettext('notify.phone', 'Phone Notices', 'csg', 'label')),
    ('notify.print', oils_i18n_gettext('notify.print', 'Print Notices', 'csg', 'label'))
;

COMMIT;


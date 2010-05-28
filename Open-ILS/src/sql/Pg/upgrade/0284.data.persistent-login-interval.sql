BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0284'); -- Scott McKellar

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
VALUES (
    'auth.persistent_login_interval',
    oils_i18n_gettext('auth.persistent_login_interval', 'Persistent Login Duration', 'coust', 'label'),
    oils_i18n_gettext('auth.persistent_login_interval', 'How long a persistent login lasts.  E.g. ''2 weeks''', 'coust', 'description'),
    'interval'
);

COMMIT;

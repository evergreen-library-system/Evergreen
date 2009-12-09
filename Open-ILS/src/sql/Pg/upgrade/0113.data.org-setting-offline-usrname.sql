BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0113');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.offline.username_allowed',
        oils_i18n_gettext('circ.offline.username_allowed', 'Offline: Patron Usernames Allowed', 'coust', 'label'),
        oils_i18n_gettext('circ.offline.username_allowed', 'During offline circulations, allow patrons to identify themselves with usernames in addition to barcode.  For this setting to work, a barcode format must also be defined', 'coust', 'description'),
        'bool'
    );

COMMIT;

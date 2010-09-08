BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0388'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class ) VALUES (
        'ui.patron.default_ident_type',
        oils_i18n_gettext(
            'ui.patron.default_ident_type',
            'GUI: Default Ident Type for Patron Registration', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'ui.patron.default_ident_type',
            'This is the default Ident Type for new users in the patron editor.',
            'coust', 
            'description'),
        'link',
        'cit'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'ui.patron.default_country',
        oils_i18n_gettext(
            'ui.patron.default_country',
            'GUI: Default Country for New Addresses in Patron Editor', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'ui.patron.default_country',
            'This is the default Country for new addresses in the patron editor.',
            'coust', 
            'description'),
        'string'
);

COMMIT;

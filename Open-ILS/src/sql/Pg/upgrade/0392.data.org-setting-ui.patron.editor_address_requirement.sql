BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0392'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'ui.patron.registration.require_address',
        oils_i18n_gettext(
            'ui.patron.registration.require_address',
            'GUI: Require at least one address for Patron Registration', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'ui.patron.registration.require_address',
            'Enforces a requirement for having at least one address for a patron during registration.',
            'coust', 
            'description'),
        'bool'
);

COMMIT;

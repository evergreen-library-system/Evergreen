BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0290'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.password_reset_request_requires_matching_email',
        oils_i18n_gettext(
            'circ.password_reset_request_requires_matching_email',
            'Circulation: Require matching email address for password reset requests', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'circ.password_reset_request_requires_matching_email',
            'Circulation: Require matching email address for password reset requests', 
            'coust', 
            'description'),
        'bool'
);

COMMIT;

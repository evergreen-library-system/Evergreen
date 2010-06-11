BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0305'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.holds.expired_patron_block',
        oils_i18n_gettext(
            'circ.holds.expired_patron_block',
            'Circulation: Block hold request if hold recipient privileges have expired', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'circ.holds.expired_patron_block',
            'Circulation: Block hold request if hold recipient privileges have expired', 
            'coust', 
            'description'),
        'bool'
);

COMMIT;

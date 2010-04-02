BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0227'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'acq.holds.allow_holds_from_purchase_request',
        oils_i18n_gettext(
            'acq.holds.allow_holds_from_purchase_request', 
            'Allows patrons to create automatic holds from purchase requests.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'acq.holds.allow_holds_from_purchase_request', 
            'Allows patrons to create automatic holds from purchase requests.', 
            'coust', 
            'description'),
        'bool'
);

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0080');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'circ.max_fine.cap_at_price',
        oils_i18n_gettext('circ.max_fine.cap_at_price', 'Circ: Cap Max Fine at Item Price', 'coust', 'label'),
        oils_i18n_gettext('circ.max_fine.cap_at_price', 'This prevents the system from charging more than the item price in overdue fines', 'coust', 'description'),
        'bool' 
    );

COMMIT;

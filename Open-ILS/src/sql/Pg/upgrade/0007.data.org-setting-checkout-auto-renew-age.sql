BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0007');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.checkout_auto_renew_age',
    'Checkout auto renew age',
    'When an item has been checked out for at least this amount of time, an attempt to check out the item to the patron that it is already checked out to will simply renew the circulation',
    'interval'
);

COMMIT;


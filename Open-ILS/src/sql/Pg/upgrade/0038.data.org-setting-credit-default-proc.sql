BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0038'); -- senator

UPDATE permission.perm_list
    SET code = 'UPDATE_ORG_UNIT_SETTING.credit.payments.allow'
    WHERE code = 'UPDATE_ORG_UNIT_SETTING.global.credit.allow';

UPDATE config.org_unit_setting_type
    SET name = 'credit.payments.allow'
    WHERE name = 'global.credit.allow';

UPDATE config.org_unit_setting_type
    SET name = REGEXP_REPLACE(name, E'global\.', '')
    WHERE name LIKE 'global.credit.%';

UPDATE config.org_unit_setting_type
    SET label = 'Credit card processing: AuthorizeNet enabled'
    WHERE name = 'credit.processor.authorizenet.enabled';

UPDATE config.org_unit_setting_type
    SET label = 'Credit card processing: PayPal enabled'
    WHERE name = 'credit.processor.paypal.enabled';

INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'credit.processor.default',
        'Credit card processing: Name default credit processor',
        'This might be "AuthorizeNet", "PayPal", etc.',
        'string'
    );


COMMIT;

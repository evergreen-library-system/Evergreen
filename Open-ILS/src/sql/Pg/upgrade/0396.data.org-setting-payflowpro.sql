BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0396'); -- senator

INSERT INTO permission.perm_list (code, description) VALUES
    ('VIEW_CREDIT_CARD_PROCESSING',
        'View org unit settings related to credit card processing'),
    ('ADMIN_CREDIT_CARD_PROCESSING',
        'Update org unit settings related to credit card processing');

INSERT INTO config.org_unit_setting_type (
    name, label, description, datatype
) VALUES
    ('credit.processor.payflowpro.enabled',
        'Credit card processing: Enable PayflowPro payments',
        'This is NOT the same thing as the settings labeled with just "PayPal."',
        'bool'
    ),
    ('credit.processor.payflowpro.login',
        'Credit card processing: PayflowPro login/merchant ID',
        'Often the same thing as the PayPal manager login',
        'string'
    ),
    ('credit.processor.payflowpro.password',
        'Credit card processing: PayflowPro password',
        'PayflowPro password',
        'string'
    ),
    ('credit.processor.payflowpro.testmode',
        'Credit card processing: PayflowPro test mode',
        'Do not really process transactions, but stay in test mode - uses pilot-payflowpro.paypal.com instead of the usual host',
        'bool'
    ),
    ('credit.processor.payflowpro.vendor',
        'Credit card processing: PayflowPro vendor',
        'Often the same thing as the login',
        'string'
    ),
    ('credit.processor.payflowpro.partner',
        'Credit card processing: PayflowPro partner',
        'Often "PayPal" or "VeriSign", sometimes others',
        'string'
    );

UPDATE config.org_unit_setting_type
    SET description = 'This can be "AuthorizeNet", "PayPal" (for the Website Payment Pro API), or "PayflowPro".'
    WHERE name = 'credit.processor.default';

UPDATE config.org_unit_setting_type
    SET view_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'VIEW_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor%' AND view_perm IS NULL;

UPDATE config.org_unit_setting_type
    SET update_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'ADMIN_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor%' AND update_perm IS NULL;

COMMIT;

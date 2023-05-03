BEGIN;

SELECT evergreen.upgrade_deps_block_check('1371', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

    ( 'credit.processor.smartpay.enabled', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.enabled',
        'Enable SmartPAY payments',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.enabled',
        'Enable SmartPAY payments',
        'coust', 'description'),
    'bool', null)

,( 'credit.processor.smartpay.location_id', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.location_id',
        'SmartPAY location ID',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.location_id',
        'SmartPAY location ID")',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.smartpay.customer_id', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.customer_id',
        'SmartPAY customer ID',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.customer_id',
        'SmartPAY customer ID',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.smartpay.login', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.login',
        'SmartPAY login name',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.login',
        'SmartPAY login name',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.smartpay.password', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.password',
        'SmartPAY password',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.password',
        'SmartPAY password',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.smartpay.api_key', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.api_key',
        'SmartPAY API key',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.api_key',
        'SmartPAY API key',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.smartpay.server', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.server',
        'SmartPAY server name',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.server',
        'SmartPAY server name',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.smartpay.port', 'credit',
    oils_i18n_gettext('credit.processor.smartpay.port',
        'SmartPAY server port',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.smartpay.port',
        'SmartPAY server port',
        'coust', 'description'),
    'string', null)
;

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext('credit.processor.default',
        'This might be "AuthorizeNet", "PayPal", "PayflowPro", "SmartPAY", or "Stripe".',
        'coust', 'description')
WHERE name = 'credit.processor.default' AND description = 'This might be "AuthorizeNet", "PayPal", "PayflowPro", or "Stripe".'; -- don't clobber local edits or i18n

UPDATE config.org_unit_setting_type
    SET view_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'VIEW_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor.smartpay.%' AND view_perm IS NULL;

UPDATE config.org_unit_setting_type
    SET update_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'ADMIN_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor.smartpay.%' AND update_perm IS NULL;

COMMIT;

BEGIN;

SELECT evergreen.upgrade_deps_block_check('1271', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description, update_perm, view_perm)
VALUES (
    'credit',
    'credit.processor.stripe.currency', 'string',
    oils_i18n_gettext(
        'credit.processor.stripe.currency',
        'Stripe ISO 4217 currency code',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'credit.processor.stripe.currency',
        'Use an all lowercase version of a Stripe-supported ISO 4217 currency code.  Defaults to "usd"',
        'coust',
        'description'
    ),
    (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_CREDIT_CARD_PROCESSING'),
    (SELECT id FROM permission.perm_list WHERE code = 'VIEW_CREDIT_CARD_PROCESSING')
);

COMMIT;

BEGIN;


SELECT evergreen.upgrade_deps_block_check('0863', :eg_version);


-- cheat sheet for enabling Stripe payments:
--  'credit.payments.allow' must be true, and among other things it drives the
--      opac to render a payment form at all
--  NEW 'credit.processor.stripe.enabled' must be true  (kind of redundant but
--      my fault for setting the precedent with c.p.{authorizenet|paypal|payflowpro}.enabled)
--  'credit.default.processor' must be 'Stripe'
--  NEW 'credit.processor.stripe.pubkey' must be set
--  NEW 'credit.processor.stripe.secretkey' must be set

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

    ( 'credit.processor.stripe.enabled', 'credit',
    oils_i18n_gettext('credit.processor.stripe.enabled',
        'Enable Stripe payments',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.stripe.enabled',
        'Enable Stripe payments',
        'coust', 'description'),
    'bool', null)

,( 'credit.processor.stripe.pubkey', 'credit',
    oils_i18n_gettext('credit.processor.stripe.pubkey',
        'Stripe publishable key',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.stripe.pubkey',
        'Stripe publishable key',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.stripe.secretkey', 'credit',
    oils_i18n_gettext('credit.processor.stripe.secretkey',
        'Stripe secret key',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.stripe.secretkey',
        'Stripe secret key',
        'coust', 'description'),
    'string', null)
;

UPDATE config.org_unit_setting_type
SET description = 'This might be "AuthorizeNet", "PayPal", "PayflowPro", or "Stripe".'
WHERE name = 'credit.processor.default' AND description = 'This might be "AuthorizeNet", "PayPal", etc.'; -- don't clobber local edits or i18n

COMMIT;

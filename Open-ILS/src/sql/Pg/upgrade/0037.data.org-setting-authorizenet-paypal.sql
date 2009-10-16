-- org_unit setting types
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0037');

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES

( 'global.credit.processor.authorizenet.enabled',
    'Credit card processing: Enable AuthorizeNet payments',
    '',
    'bool' ),

( 'global.credit.processor.authorizenet.login',
    'Credit card processing: AuthorizeNet login',
    '',
    'string' ),

( 'global.credit.processor.authorizenet.password',
    'Credit card processing: AuthorizeNet password',
    '',
    'string' ),

( 'global.credit.processor.authorizenet.server',
    'Credit card processing: AuthorizeNet server',
    'Required if using a developer/test account with AuthorizeNet',
    'string' ),

( 'global.credit.processor.authorizenet.testmode',
    'Credit card processing: AuthorizeNet test mode',
    '',
    'bool' ),

( 'global.credit.processor.paypal.enabled',
    'Credit card processing: Enable PayPal payments',
    '',
    'bool' ),
( 'global.credit.processor.paypal.login',
    'Credit card processing: PayPal login',
    '',
    'string' ),
( 'global.credit.processor.paypal.password',
    'Credit card processing: PayPal password',
    '',
    'string' ),
( 'global.credit.processor.paypal.signature',
    'Credit card processing: PayPal signature',
    '',
    'string' ),
( 'global.credit.processor.paypal.testmode',
    'Credit card processing: PayPal test mode',
    '',
    'bool' );

COMMIT;

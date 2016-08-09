BEGIN;

SELECT evergreen.upgrade_deps_block_check('0987', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype )
    VALUES (
        'ui.circ.billing.amount_limit', 'gui',
        oils_i18n_gettext(
            'ui.circ.billing.amount_limit',
            'Maximum payment amount allowed.',
            'coust', 'label'),
        oils_i18n_gettext(
            'ui.circ.billing.amount_limit',
            'The payment amount in the Patron Bills interface may not exceed the value of this setting.',
            'coust', 'description'),
        'currency'
    );

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype )
    VALUES (
        'ui.circ.billing.amount_warn', 'gui',
        oils_i18n_gettext(
            'ui.circ.billing.amount_warn',
            'Payment amount threshold for Are You Sure? dialog.',
            'coust', 'label'),
        oils_i18n_gettext(
            'ui.circ.billing.amount_warn',
            'In the Patron Bills interface, a payment attempt will warn if the amount exceeds the value of this setting.',
            'coust', 'description'),
        'currency'
    );

COMMIT;

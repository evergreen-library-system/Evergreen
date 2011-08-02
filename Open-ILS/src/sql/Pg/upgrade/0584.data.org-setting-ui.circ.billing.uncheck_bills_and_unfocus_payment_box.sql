-- Evergreen DB patch XXXX.data.org-setting-ui.circ.billing.uncheck_bills_and_unfocus_payment_box.sql
--
-- New org setting ui.circ.billing.uncheck_bills_and_unfocus_payment_box
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0584', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
        oils_i18n_gettext(
            'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
            'GUI: Uncheck bills by default in the patron billing interface',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
            'Uncheck bills by default in the patron billing interface,'
            || ' and focus on the Uncheck All button instead of the'
            || ' Payment Received field.',
            'coust',
            'description'
        ),
        'bool'
    );

COMMIT;

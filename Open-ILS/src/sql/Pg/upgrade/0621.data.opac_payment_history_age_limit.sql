-- Evergreen DB patch XXXX.data.opac_payment_history_age_limit.sql

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0621', :eg_version);

INSERT into config.org_unit_setting_type (name, label, description, datatype)
VALUES (
    'opac.payment_history_age_limit',
    oils_i18n_gettext('opac.payment_history_age_limit',
        'OPAC: Payment History Age Limit', 'coust', 'label'),
    oils_i18n_gettext('opac.payment_history_age_limit',
        'The OPAC should not display payments by patrons that are older than any interval defined here.', 'coust', 'label'),
    'interval'
);

COMMIT;

BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE money.adjustment_payment (
    billing BIGINT REFERENCES money.billing (id) ON DELETE SET NULL
) INHERITS (money.bnm_payment);
ALTER TABLE money.adjustment_payment ADD PRIMARY KEY (id);
CREATE INDEX money_adjustment_id_idx ON money.adjustment_payment (id);
CREATE INDEX money_adjustment_payment_xact_idx ON money.adjustment_payment (xact);
CREATE INDEX money_adjustment_payment_bill_idx ON money.adjustment_payment (billing);
CREATE INDEX money_adjustment_payment_payment_ts_idx ON money.adjustment_payment (payment_ts);
CREATE INDEX money_adjustment_payment_accepting_usr_idx ON money.adjustment_payment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.adjustment_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('adjustment_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.adjustment_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('adjustment_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.adjustment_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('adjustment_payment');

-- Insert new org. unit settings.
INSERT INTO config.org_unit_setting_type 
       (name, grp, datatype, label, description)
VALUES
       ('bill.prohibit_negative_balance_default',
        'finance', 'bool',
        oils_i18n_gettext(
            'bill.prohibit_negative_balance_default',
            'Prohibit negative balance on bills (DEFAULT)',
            'coust', 'label'),
        oils_i18n_gettext(
            'bill.prohibit_negative_balance_default',
            'Default setting to prevent credits on circulation related bills',
            'coust', 'description')
       ),
       ('bill.prohibit_negative_balance_on_overdues',
        'finance', 'bool',
        oils_i18n_gettext(
            'bill.prohibit_negative_balance_on_overdues',
            'Prohibit negative balance on bills for overdue materials',
            'coust', 'label'),
        oils_i18n_gettext(
            'bill.prohibit_negative_balance_on_overdues',
            'Prevent credits on bills for overdue materials',
            'coust', 'description')
       ),
       ('bill.prohibit_negative_balance_on_lost',
        'finance', 'bool',
        oils_i18n_gettext(
            'bill.prohibit_negative_balance_on_lost',
            'Prohibit negative balance on bills for lost materials',
            'coust', 'label'),
        oils_i18n_gettext(
            'bill.prohibit_negative_balance_on_lost',
            'Prevent credits on bills for lost/long-overde materials',
            'coust', 'description')
       ),
       ('bill.negative_balance_interval_default',
        'finance', 'interval',
        oils_i18n_gettext(
            'bill.negative_balance_interval_default',
            'Negative Balance Interval (DEFAULT)',
            'coust', 'label'),
        oils_i18n_gettext(
            'bill.negative_balance_interval_default',
            'Amount of time after which no negative balances or credits are allowed on circulation bills',
            'coust', 'description')
       ),
       ('bill.negative_balance_interval_on_overdues',
        'finance', 'interval',
        oils_i18n_gettext(
            'bill.negative_balance_interval_on_overdues',
            'Negative Balance Interval for Overdues',
            'coust', 'label'),
        oils_i18n_gettext(
            'bill.negative_balance_interval_on_overdues',
            'Amount of time after which no negative balances or credits are allowed on bills for overdue materials',
            'coust', 'description')
       ),
       ('bill.negative_balance_interval_on_lost',
        'finance', 'interval',
        oils_i18n_gettext(
            'bill.negative_balance_interval_on_lost',
            'Negative Balance Interval for Lost',
            'coust', 'label'),
        oils_i18n_gettext(
            'bill.negative_balance_interval_on_lost',
            'Amount of time after which no negative balances or credits are allowed on bills for lost/long overdue materials',
            'coust', 'description')
       );

COMMIT;

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0921', :eg_version);

CREATE TABLE money.account_adjustment (
    billing BIGINT REFERENCES money.billing (id) ON DELETE SET NULL
) INHERITS (money.bnm_payment);
ALTER TABLE money.account_adjustment ADD PRIMARY KEY (id);
CREATE INDEX money_adjustment_id_idx ON money.account_adjustment (id);
CREATE INDEX money_account_adjustment_xact_idx ON money.account_adjustment (xact);
CREATE INDEX money_account_adjustment_bill_idx ON money.account_adjustment (billing);
CREATE INDEX money_account_adjustment_payment_ts_idx ON money.account_adjustment (payment_ts);
CREATE INDEX money_account_adjustment_accepting_usr_idx ON money.account_adjustment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.account_adjustment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('account_adjustment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.account_adjustment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('account_adjustment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.account_adjustment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('account_adjustment');

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
            'Default setting to prevent negative balances (refunds) on circulation related bills',
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
            'Prevent negative balances (refunds) on bills for overdue materials',
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
            'Prevent negative balances (refunds) on bills for lost/long-overdue materials',
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
            'Amount of time after which no negative balances (refunds) are allowed on circulation bills',
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
            'Amount of time after which no negative balances (refunds) are allowed on bills for overdue materials',
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
            'Amount of time after which no negative balances (refunds) are allowed on bills for lost/long overdue materials',
            'coust', 'description')
       );

COMMIT;

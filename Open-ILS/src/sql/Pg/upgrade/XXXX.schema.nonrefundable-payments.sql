BEGIN;

ALTER TABLE money.aged_payment ADD COLUMN refundable BOOL;

CREATE OR REPLACE VIEW money.payment_view AS
    SELECT  p.*,
            c.relname AS payment_type,
            COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.payment p
            JOIN pg_class c ON (p.tableoid = c.oid)
            LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable');

CREATE OR REPLACE VIEW money.non_drawer_payment_view AS
    SELECT  p.*, c.relname AS payment_type, COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.bnm_payment p
            JOIN pg_class c ON p.tableoid = c.oid
            LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable')
      WHERE c.relname NOT IN ('cash_payment','check_payment','credit_card_payment','debit_card_payment');

CREATE OR REPLACE VIEW money.cashdrawer_payment_view AS
    SELECT  ou.id AS org_unit,
        ws.id AS cashdrawer,
        t.payment_type AS payment_type,
        p.payment_ts AS payment_ts,
        p.amount AS amount,
        p.voided AS voided,
        p.note AS note,
        t.refundable AS refundable
      FROM  actor.org_unit ou
        JOIN actor.workstation ws ON (ou.id = ws.owning_lib)
        LEFT JOIN money.bnm_desk_payment p ON (ws.id = p.cash_drawer)
        LEFT JOIN money.payment_view t ON (p.id = t.id);

CREATE OR REPLACE VIEW money.desk_payment_view AS
    SELECT  p.*,c.relname AS payment_type,COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.bnm_desk_payment p
        JOIN pg_class c ON (p.tableoid = c.oid)
        LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable');

CREATE OR REPLACE VIEW money.bnm_payment_view AS
    SELECT  p.*,c.relname AS payment_type,COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.bnm_payment p
        JOIN pg_class c ON (p.tableoid = c.oid)
        LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable');

CREATE OR REPLACE VIEW money.payment_view_for_aging AS
    SELECT p.id,
        p.xact,
        p.payment_ts,
        p.voided,
        p.amount,
        p.note,
        p.payment_type,
        bnm.accepting_usr,
        bnmd.cash_drawer,
        maa.billing,
        p.refundable
    FROM money.payment_view p
    LEFT JOIN money.bnm_payment bnm ON bnm.id = p.id
    LEFT JOIN money.bnm_desk_payment bnmd ON bnmd.id = p.id
    LEFT JOIN money.account_adjustment maa ON maa.id = p.id;

CREATE OR REPLACE FUNCTION money.mbts_refundable_balance_check () RETURNS TRIGGER AS $$
BEGIN
    -- Check if the raw xact balance has gone negative (balance_owed may be adjusted by this very trigger!)
    IF NEW.total_owed - NEW.total_paid < 0.0 THEN

        -- If negative (a refund), we increase it by the non-refundable payment total, but only up to 0.0
        SELECT  LEAST(
                    COALESCE(SUM(amount),0.0) -- non-refundable payment total
                      + (NEW.total_owed - NEW.total_paid), -- raw balance
                    0.0
                ) INTO NEW.balance_owed -- update the NEW record
          FROM  money.payment_view
          WHERE NOT refundable
                AND xact = NEW.id
                AND NOT voided;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_refund_balance_check_tgr BEFORE UPDATE ON money.materialized_billable_xact_summary FOR EACH ROW EXECUTE PROCEDURE money.mbts_refundable_balance_check ();

INSERT INTO config.global_flag (name, label, enabled) VALUES
( 'money.account_adjustment.is_refundable',
  oils_i18n_gettext( 'money.account_adjustment.is_refundable', 'Money: Enable to allow account adjustments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.forgive_payment.is_refundable',
  oils_i18n_gettext( 'money.forgive_payment.is_refundable', 'Money: Enable to allow forgive payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.work_payment.is_refundable',
  oils_i18n_gettext( 'money.work_payment.is_refundable', 'Money: Enable to allow work payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.credit_payment.is_refundable',
  oils_i18n_gettext( 'money.credit_payment.is_refundable', 'Money: Enable to allow credit payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.goods_payment.is_refundable',
  oils_i18n_gettext( 'money.goods_payment.is_refundable', 'Money: Enable to allow goods payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.credit_card_payment.is_refundable',
  oils_i18n_gettext( 'money.credit_card_payment.is_refundable', 'Money: Enable to allow credit card payments to be refundable to patrons', 'cgf', 'label'),
  TRUE ),
( 'money.cash_payment.is_refundable',
  oils_i18n_gettext( 'money.cash_payment.is_refundable', 'Money: Enable to allow cash payments to be refundable to patrons', 'cgf', 'label'),
  TRUE ),
( 'money.check_payment.is_refundable',
  oils_i18n_gettext( 'money.check_payment.is_refundable', 'Money: Enable to allow check payments to be refundable to patrons', 'cgf', 'label'),
  TRUE ),
( 'money.debit_card_payment.is_refundable',
  oils_i18n_gettext( 'money.debit_card_payment.is_refundable', 'Money: Enable to allow debit card payments to be refundable to patrons', 'cgf', 'label'),
  TRUE )
;

COMMIT;


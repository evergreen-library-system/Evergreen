BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0174'); -- miker

-- The view should supply defaults for numeric (amount) columns
CREATE OR REPLACE VIEW money.billable_xact_summary AS
    SELECT  xact.id,
        xact.usr,
        xact.xact_start,
        xact.xact_finish,
        COALESCE(credit.amount, 0.0::numeric) AS total_paid,
        credit.payment_ts AS last_payment_ts,
        credit.note AS last_payment_note,
        credit.payment_type AS last_payment_type,
        COALESCE(debit.amount, 0.0::numeric) AS total_owed,
        debit.billing_ts AS last_billing_ts,
        debit.note AS last_billing_note,
        debit.billing_type AS last_billing_type,
        COALESCE(debit.amount, 0.0::numeric) - COALESCE(credit.amount, 0.0::numeric) AS balance_owed,
        p.relname AS xact_type
      FROM  money.billable_xact xact
        JOIN pg_class p ON xact.tableoid = p.oid
        LEFT JOIN (
            SELECT  billing.xact,
                sum(billing.amount) AS amount,
                max(billing.billing_ts) AS billing_ts,
                last(billing.note) AS note,
                last(billing.billing_type) AS billing_type
              FROM  money.billing
              WHERE billing.voided IS FALSE
              GROUP BY billing.xact
            ) debit ON xact.id = debit.xact
        LEFT JOIN (
            SELECT  payment_view.xact,
                sum(payment_view.amount) AS amount,
                max(payment_view.payment_ts) AS payment_ts,
                last(payment_view.note) AS note,
                last(payment_view.payment_type) AS payment_type
              FROM  money.payment_view
              WHERE payment_view.voided IS FALSE
              GROUP BY payment_view.xact
            ) credit ON xact.id = credit.xact
      ORDER BY debit.billing_ts, credit.payment_ts;

-- And the "add" trigger functions should protect against existing NULLed values, just in case
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_add () RETURNS TRIGGER AS $$
BEGIN
    IF NOT NEW.voided THEN
        UPDATE  money.materialized_billable_xact_summary
          SET   total_owed = COALESCE(total_owed, 0.0::numeric) + NEW.amount,
            last_billing_ts = NEW.billing_ts,
            last_billing_note = NEW.note,
            last_billing_type = NEW.billing_type,
            balance_owed = balance_owed + NEW.amount
          WHERE id = NEW.xact;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION money.materialized_summary_payment_add () RETURNS TRIGGER AS $$
BEGIN
    IF NOT NEW.voided THEN
        UPDATE  money.materialized_billable_xact_summary
          SET   total_paid = COALESCE(total_paid, 0.0::numeric) + NEW.amount,
            last_payment_ts = NEW.payment_ts,
            last_payment_note = NEW.note,
            last_payment_type = TG_ARGV[0],
            balance_owed = balance_owed - NEW.amount
          WHERE id = NEW.xact;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Refresh the mat view with the corrected underlying view
TRUNCATE money.materialized_billable_xact_summary;
INSERT INTO money.materialized_billable_xact_summary SELECT * FROM money.billable_xact_summary;

COMMIT;



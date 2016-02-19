--Upgrade Script for 2.8.5 to 2.8.6
\set eg_version '''2.8.6'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.6', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0950', :eg_version); 

CREATE OR REPLACE FUNCTION money.materialized_summary_billing_del () RETURNS TRIGGER AS $$
DECLARE
        prev_billing    money.billing%ROWTYPE;
        old_billing     money.billing%ROWTYPE;
BEGIN
        SELECT * INTO prev_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1 OFFSET 1;
        SELECT * INTO old_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1;

        IF OLD.id = old_billing.id THEN
                UPDATE  money.materialized_billable_xact_summary
                  SET   last_billing_ts = prev_billing.billing_ts,
                        last_billing_note = prev_billing.note,
                        last_billing_type = prev_billing.billing_type
                  WHERE id = OLD.xact;
        END IF;

        IF NOT OLD.voided THEN
                UPDATE  money.materialized_billable_xact_summary
                  SET   total_owed = total_owed - OLD.amount,
                        balance_owed = balance_owed - OLD.amount
                  WHERE id = OLD.xact;
        END IF;

        RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0628');

-- acq.fund_combined_balance and acq.fund_spent_balance are unchanged,
-- however we need to drop them to recreate the other views.
-- we need to drop all our views because we change the number of columns
-- for example, debit_total does not need an encumberance column when we 
-- have a sepearate total for that.

DROP VIEW acq.fund_spent_balance;
DROP VIEW acq.fund_combined_balance;
DROP VIEW acq.fund_encumbrance_total;
DROP VIEW acq.fund_spent_total;
DROP VIEW acq.fund_debit_total;

CREATE OR REPLACE VIEW acq.fund_debit_total AS
    SELECT  fund.id AS fund, 
            sum(COALESCE(fund_debit.amount, 0::numeric)) AS amount
    FROM acq.fund fund
        LEFT JOIN acq.fund_debit fund_debit ON fund.id = fund_debit.fund
    GROUP BY fund.id;

CREATE OR REPLACE VIEW acq.fund_encumbrance_total AS
    SELECT 
        fund.id AS fund, 
        sum(COALESCE(fund_debit.amount, 0::numeric)) AS amount 
    FROM acq.fund fund
        LEFT JOIN acq.fund_debit fund_debit ON fund.id = fund_debit.fund 
    WHERE fund_debit.encumbrance GROUP BY fund.id;

CREATE OR REPLACE VIEW acq.fund_spent_total AS
    SELECT  fund.id AS fund, 
            sum(COALESCE(fund_debit.amount, 0::numeric)) AS amount 
    FROM acq.fund fund
        LEFT JOIN acq.fund_debit fund_debit ON fund.id = fund_debit.fund 
    WHERE NOT fund_debit.encumbrance 
    GROUP BY fund.id;

CREATE OR REPLACE VIEW acq.fund_combined_balance AS
    SELECT  c.fund, 
            c.amount - COALESCE(d.amount, 0.0) AS amount
    FROM acq.fund_allocation_total c
    LEFT JOIN acq.fund_debit_total d USING (fund);

CREATE OR REPLACE VIEW acq.fund_spent_balance AS
    SELECT  c.fund,
            c.amount - COALESCE(d.amount,0.0) AS amount
      FROM  acq.fund_allocation_total c
            LEFT JOIN acq.fund_spent_total d USING (fund);

COMMIT;

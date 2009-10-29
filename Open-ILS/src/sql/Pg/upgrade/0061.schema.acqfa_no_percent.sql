BEGIN;

-- Script to eliminate acq.fund_allocation.percent, which has been moved to the
-- acq.fund_allocation_percent table.

INSERT INTO config.upgrade_log (version) VALUES ('0061');  -- Scott McKellar

-- If the following step fails, it's probably because there are still some non-null percent values in
-- acq.fund_allocation.  They should have all been converted to amounts, and then set to null, by a
-- previous upgrade script, 0049.schema.acq_funding_allocation_percent.sql.  If there are any non-null
-- values, then either that script didn't run, or it didn't work, or some non-null values slipped in
-- afterwards.

-- To convert any remaining percents to amounts: create, run, and then drop the temporary stored
-- procedure acq.fund_alloc_percent_val as defined in 0049.schema.acq_funding_allocation_percent.sql.

ALTER TABLE acq.fund_allocation
ALTER COLUMN amount SET NOT NULL;

CREATE OR REPLACE VIEW acq.fund_allocation_total AS
    SELECT  fund,
            SUM(a.amount * acq.exchange_ratio(s.currency_type, f.currency_type))::NUMERIC(100,2) AS amount
    FROM acq.fund_allocation a
         JOIN acq.fund f ON (a.fund = f.id)
         JOIN acq.funding_source s ON (a.funding_source = s.id)
    GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_allocation_total AS
    SELECT  funding_source,
            SUM(a.amount)::NUMERIC(100,2) AS amount
    FROM  acq.fund_allocation a
    GROUP BY 1;

ALTER TABLE acq.fund_allocation
DROP COLUMN percent;

COMMIT;
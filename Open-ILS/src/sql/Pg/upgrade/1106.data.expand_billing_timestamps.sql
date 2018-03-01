BEGIN;

SELECT evergreen.upgrade_deps_block_check('1106', :eg_version);

ALTER TABLE money.billing
	ADD COLUMN create_date TIMESTAMP WITH TIME ZONE,
	ADD COLUMN period_start    TIMESTAMP WITH TIME ZONE,
	ADD COLUMN period_end  TIMESTAMP WITH TIME ZONE;

--Disable materialized update trigger
--It takes forever, and doesn't matter yet for what we are doing, as the
--view definition is unchanged (still using billing_ts)
ALTER TABLE money.billing DISABLE TRIGGER mat_summary_upd_tgr;

--Limit to btype=1 / 'Overdue Materials'
--Update day-granular fines first (i.e. 24 hour, 1 day, 2 day, etc., all of which are multiples of 86400 seconds), and simply remove the time portion of timestamp
UPDATE money.billing mb
	SET period_start = date_trunc('day', billing_ts), period_end = date_trunc('day', billing_ts) + (ac.fine_interval - '1 second')
	FROM action.circulation ac
WHERE mb.xact = ac.id
	AND mb.btype = 1
	AND (EXTRACT(EPOCH FROM ac.fine_interval))::integer % 86400 = 0;

--Update fines for non-day intervals
UPDATE money.billing mb
	SET period_start = billing_ts - ac.fine_interval + interval '1 sec', period_end = billing_ts
	FROM action.circulation ac
WHERE mb.xact = ac.id
	AND mb.btype = 1
	AND (EXTRACT(EPOCH FROM ac.fine_interval))::integer % 86400 > 0;

SET CONSTRAINTS ALL IMMEDIATE;
UPDATE money.billing SET create_date = COALESCE(period_start, billing_ts);

--Re-enable update trigger
ALTER TABLE money.billing ENABLE TRIGGER mat_summary_upd_tgr;

ALTER TABLE money.billing ALTER COLUMN create_date SET DEFAULT NOW();
ALTER TABLE money.billing ALTER COLUMN create_date SET NOT NULL;

CREATE INDEX m_b_create_date_idx ON money.billing (create_date);
CREATE INDEX m_b_period_start_idx ON money.billing (period_start);
CREATE INDEX m_b_period_end_idx ON money.billing (period_end);

CREATE OR REPLACE FUNCTION money.maintain_billing_ts () RETURNS TRIGGER AS $$
BEGIN
	NEW.billing_ts := COALESCE(NEW.period_end, NEW.create_date);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;
CREATE TRIGGER maintain_billing_ts_tgr BEFORE INSERT OR UPDATE ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.maintain_billing_ts();

COMMIT;

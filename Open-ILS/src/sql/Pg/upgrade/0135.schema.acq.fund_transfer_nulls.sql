BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0135'); -- Scott McKellar

-- Make dest_fund and dest_amount nullable in order to accommodate
-- deallocations; i.e. when we move money out of a fund without
-- putting it into some other fund.

ALTER TABLE acq.fund_transfer
	ALTER COLUMN dest_fund DROP NOT NULL;

ALTER TABLE acq.fund_transfer
	ALTER COLUMN dest_amount DROP NOT NULL;

COMMIT;

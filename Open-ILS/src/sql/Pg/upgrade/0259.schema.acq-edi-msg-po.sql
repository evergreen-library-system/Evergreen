BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0259'); -- Scott McKellar

-- Warning: Due to an oversight, the acq.edi_message table was added via an
-- upgrade script, but the CREATE TABLE statement was never added to the
-- 200.schema.acq.sql script (till now).

-- If you have rebuilt your system from scratch since then, you may find that
-- the following ALTER will fail because the table doesn't exist yet.

-- Solution: run the relevant CREATE TABLE statement from 200.schema.acq.sql
-- instead of this upgrade script.  You may also want to manually insert a
-- row into config.upgrade_log, as per the above.

ALTER TABLE acq.edi_message
    ADD COLUMN purchase_order INT
	REFERENCES acq.purchase_order
	DEFERRABLE INITIALLY DEFERRED;

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0178'); -- Scott McKellar

ALTER TABLE acq.lineitem_detail
	ADD COLUMN cancel_reason        INT REFERENCES acq.cancel_reason( id )
	                                    DEFERRABLE INITIALLY DEFERRED;

COMMIT;

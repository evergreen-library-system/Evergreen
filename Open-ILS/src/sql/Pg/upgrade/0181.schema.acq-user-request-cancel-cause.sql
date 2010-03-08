BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0181'); -- Scott McKellar

ALTER TABLE acq.user_request
	ADD COLUMN cancel_reason   INT
		REFERENCES acq.cancel_reason( id ) DEFERRABLE INITIALLY DEFERRED;

COMMIT;

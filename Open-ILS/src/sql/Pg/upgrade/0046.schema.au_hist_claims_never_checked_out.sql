BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0046'); -- Scott McKellar

ALTER TABLE AUDITOR.actor_usr_history ADD COLUMN 
	claims_never_checked_out_count INT NOT NULL DEFAULT 0;

COMMIT;

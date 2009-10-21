BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0043'); -- Scott McKellar

ALTER TABLE actor.usr ADD COLUMN
	claims_never_checked_out_count  INT         NOT NULL DEFAULT 0;

ALTER TABLE action.circulation
DROP CONSTRAINT circulation_stop_fines_check;

ALTER TABLE action.circulation
	ADD CONSTRAINT circulation_stop_fines_check
	CHECK (stop_fines IN (
        'CHECKIN','CLAIMSRETURNED','LOST','MAXFINES','RENEW','LONGOVERDUE','CLAIMSNEVERCHECKEDOUT'));

COMMIT;

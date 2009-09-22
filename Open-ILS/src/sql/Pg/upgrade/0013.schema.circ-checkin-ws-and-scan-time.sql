BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0013');

ALTER TABLE action.circulation
ADD COLUMN checkin_workstation INT
	REFERENCES actor.workstation(id)
	ON DELETE SET NULL
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.circulation
ADD COLUMN checkin_scan_time TIMESTAMPTZ;

COMMIT;


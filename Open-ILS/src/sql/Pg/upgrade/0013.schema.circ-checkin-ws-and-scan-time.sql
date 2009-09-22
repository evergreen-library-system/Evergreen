BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0013.schema.circ-checkin-ws-and-scan-time.sql');

ALTER TABLE action.circulation
ADD COLUMN checkin_workstation INT
	REFERENCES actor.workstation(id)
	ON DELETE SET NULL
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.circulation
ADD COLUMN checkin_scan_time TIMESTAMPTZ;

COMMIT;


BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0019');

ALTER TABLE action.aged_circulation
ADD COLUMN workstation INT;

ALTER TABLE action.aged_circulation
ADD COLUMN checkin_workstation INT;

ALTER TABLE action.aged_circulation
ADD COLUMN checkin_scan_time TIMESTAMPTZ;

ALTER TABLE action.aged_circulation
ADD COLUMN parent_circ BIGINT;

COMMIT;

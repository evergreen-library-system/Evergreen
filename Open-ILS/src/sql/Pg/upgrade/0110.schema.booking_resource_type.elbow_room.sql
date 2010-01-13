BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0110'); --miker

ALTER TABLE booking.resource_type ADD COLUMN elbow_room INTERVAL;

COMMIT;


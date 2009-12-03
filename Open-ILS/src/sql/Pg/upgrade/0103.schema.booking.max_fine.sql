BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0103'); -- miker

ALTER TABLE booking.resource_type ADD COLUMN max_fine NUMERIC(8,2);
ALTER TABLE booking.reservation ADD COLUMN max_fine NUMERIC(8,2);

COMMIT;

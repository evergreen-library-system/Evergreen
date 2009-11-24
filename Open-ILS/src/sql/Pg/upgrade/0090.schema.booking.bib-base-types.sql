BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0090'); -- miker

ALTER TABLE booking.resource_type DROP CONSTRAINT brt_name_once_per_owner;
ALTER TABLE booking.resource_type ADD COLUMN record BIGINT REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE booking.resource_type ADD CONSTRAINT brt_name_or_record_once_per_owner UNIQUE(owner, name, record);

COMMIT;

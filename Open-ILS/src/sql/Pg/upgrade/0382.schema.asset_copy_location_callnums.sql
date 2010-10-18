BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0382'); -- dbs

-- Start picking up call number label prefixes and suffixes
-- from asset.copy_location
ALTER TABLE asset.copy_location ADD COLUMN label_prefix TEXT;
ALTER TABLE asset.copy_location ADD COLUMN label_suffix TEXT;

COMMIT;

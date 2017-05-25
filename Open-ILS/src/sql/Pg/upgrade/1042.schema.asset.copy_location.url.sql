BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1042', :eg_version); -- mmorgan/gmcharlt

ALTER TABLE asset.copy_location
          ADD COLUMN url TEXT;

COMMIT;

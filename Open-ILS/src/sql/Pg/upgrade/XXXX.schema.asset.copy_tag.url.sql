BEGIN;

--INSERT INTO config.upgrade_log (version, applied_to) VALUES ('XXXX', :eg_version);

ALTER TABLE asset.copy_tag
          ADD COLUMN url TEXT;

COMMIT;

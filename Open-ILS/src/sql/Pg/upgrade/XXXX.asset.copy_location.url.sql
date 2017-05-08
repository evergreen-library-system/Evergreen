BEGIN;

ALTER TABLE asset.copy_location
          ADD COLUMN url TEXT;

COMMIT;

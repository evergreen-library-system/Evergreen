BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0010.schema.asset-copy-dummy-isbn.sql');

ALTER TABLE asset.copy
ADD COLUMN dummy_isbn TEXT;

ALTER TABLE auditor.asset_copy_history
ADD COLUMN dummy_isbn TEXT;

COMMIT;


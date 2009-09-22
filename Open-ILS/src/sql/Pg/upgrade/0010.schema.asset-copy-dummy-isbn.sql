BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0010');

ALTER TABLE asset.copy
ADD COLUMN dummy_isbn TEXT;

ALTER TABLE auditor.asset_copy_history
ADD COLUMN dummy_isbn TEXT;

COMMIT;


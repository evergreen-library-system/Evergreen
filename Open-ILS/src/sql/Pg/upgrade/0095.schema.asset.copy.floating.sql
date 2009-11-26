BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0095'); -- miker

ALTER TABLE asset.copy ADD COLUMN floating BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE auditor.asset_copy_history ADD COLUMN floating BOOL;

COMMIT;


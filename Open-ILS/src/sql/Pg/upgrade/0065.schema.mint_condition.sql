BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0065');

ALTER TABLE asset.copy
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE action.hold_request
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE auditor.asset_copy_history
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

COMMIT;


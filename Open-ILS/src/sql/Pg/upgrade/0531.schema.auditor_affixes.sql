BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0531'); --gmc

ALTER TABLE auditor.asset_call_number_history
    ADD COLUMN prefix INT NOT NULL DEFAULT -1,
    ADD COLUMN suffix INT NOT NULL DEFAULT -1;

ALTER TABLE auditor.asset_call_number_history
    ALTER COLUMN prefix DROP DEFAULT,
    ALTER COLUMN suffix DROP DEFAULT;

COMMIT;

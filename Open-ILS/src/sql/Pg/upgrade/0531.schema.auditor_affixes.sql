BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0531'); --gmc

ALTER TABLE auditor.asset_call_number_history
    ADD COLUMN prefix INT,
    ADD COLUMN suffix INT;

COMMIT;

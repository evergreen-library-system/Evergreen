BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0328'); -- phasefx

ALTER TABLE money.credit_card_payment ADD COLUMN cc_name TEXT;

COMMIT;

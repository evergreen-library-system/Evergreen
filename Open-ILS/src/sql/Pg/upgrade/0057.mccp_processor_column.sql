BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0057'); -- senator

ALTER TABLE money.credit_card_payment ADD COLUMN cc_processor TEXT;

COMMIT;

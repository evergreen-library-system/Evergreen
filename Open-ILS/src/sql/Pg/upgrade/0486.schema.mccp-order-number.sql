BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0486');

ALTER TABLE money.credit_card_payment ADD COLUMN cc_order_number TEXT;

COMMIT;

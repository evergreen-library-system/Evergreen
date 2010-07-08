-- If you ran this before its most recent incarnation:
-- delete from config.upgrade_log where version = '0328';
-- alter table money.credit_card_payment drop column cc_name;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0328'); -- phasefx

ALTER TABLE money.credit_card_payment ADD COLUMN cc_first_name TEXT;
ALTER TABLE money.credit_card_payment ADD COLUMN cc_last_name TEXT;

COMMIT;

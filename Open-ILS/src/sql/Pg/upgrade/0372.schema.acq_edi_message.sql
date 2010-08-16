BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0372');  -- atz

ALTER TABLE acq.edi_account ADD COLUMN vendacct TEXT;

COMMIT;

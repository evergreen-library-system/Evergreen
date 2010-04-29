BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0245');  -- atz

ALTER TABLE acq.edi_account ADD COLUMN vendcode TEXT;

COMMIT;

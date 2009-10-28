BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0060');

-- Add a san column for EDI. 
-- See: http://isbn.org/standards/home/isbn/us/san/san-qa.asp

ALTER TABLE acq.provider ADD COLUMN san INT;

COMMIT;


BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0264'); -- Scott McKellar

-- Add a message_type column

-- WARNING: because the new column is NOT NULL, this upgrade script must
-- initialize it with something if the table is not empty.  The initial
-- value, 'ORDERS', may not always be appropriate.  Massage as needed.

-- For example, if you have already processed responses, this fixes them:
-- update acq.edi_message set message_type='ORDRSP' where edi LIKE '%ORDRSP%';

ALTER TABLE acq.edi_message
	ADD COLUMN message_type TEXT;

UPDATE acq.edi_message
SET message_type = 'ORDERS';

ALTER TABLE acq.edi_message
	ALTER COLUMN message_type SET NOT NULL;

ALTER TABLE acq.edi_message
	ADD CONSTRAINT valid_message_type CHECK
		( message_type IN (
			'ORDERS',
			'ORDRSP',
			'INVOIC',
			'OSTENQ',
			'OSTRPT'
		));

-- Add a new valid value for status: 'retry'

ALTER TABLE acq.edi_message
	DROP CONSTRAINT status_value;

ALTER TABLE acq.edi_message
	ADD CONSTRAINT status_value CHECK
	( status IN (
		'new',          -- needs to be translated
		'translated',   -- needs to be processed
		'trans_error',  -- error in translation step
		'processed',    -- needs to have remote_file deleted
		'proc_error',   -- error in processing step
		'delete_error', -- error in deletion
		'retry',        -- need to retry
		'complete'      -- done
	));

COMMIT;

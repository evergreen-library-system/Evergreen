BEGIN;

-- Depending on how your edi_message table was created, one of the constraints
-- may be wrong.  The following will fix it if it's wrong, and have no effect
-- if it's right.

INSERT INTO config.upgrade_log (version) VALUES ('0266'); -- Scott McKellar

ALTER TABLE acq.edi_message
	DROP CONSTRAINT valid_message_type;

ALTER TABLE acq.edi_message
	ADD CONSTRAINT valid_message_type CHECK
		( message_type IN (
			'ORDERS',
			'ORDRSP',
			'INVOIC',
			'OSTENQ',
			'OSTRPT'
		));

COMMIT;

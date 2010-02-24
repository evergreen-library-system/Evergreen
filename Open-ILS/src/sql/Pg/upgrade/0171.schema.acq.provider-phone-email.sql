BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0171'); -- Scott McKellar

ALTER TABLE acq.provider_address
	ADD COLUMN fax_phone TEXT;

ALTER TABLE acq.provider_contact_address
	ADD COLUMN fax_phone TEXT;

ALTER TABLE acq.provider
	ADD COLUMN url TEXT;

ALTER TABLE acq.provider
	ADD COLUMN email TEXT;

ALTER TABLE acq.provider
	ADD COLUMN phone TEXT;

ALTER TABLE acq.provider
	ADD COLUMN fax_phone TEXT;

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0187'); -- Scott McKellar

ALTER TABLE acq.po_note
	ADD COLUMN vendor_public BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE acq.lineitem_note
	ADD COLUMN vendor_public BOOLEAN NOT NULL DEFAULT FALSE;

COMMIT;

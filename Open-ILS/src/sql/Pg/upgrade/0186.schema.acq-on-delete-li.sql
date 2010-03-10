BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0186'); -- Scott McKellar

ALTER TABLE acq.distribution_formula_application
	DROP CONSTRAINT distribution_formula_application_lineitem_fkey;

ALTER TABLE acq.distribution_formula_application
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_attr
	DROP CONSTRAINT lineitem_attr_lineitem_fkey;

ALTER TABLE acq.lineitem_attr
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_detail
	DROP CONSTRAINT lineitem_detail_lineitem_fkey;

ALTER TABLE acq.lineitem_detail
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_note
	DROP CONSTRAINT lineitem_note_lineitem_fkey;

ALTER TABLE acq.lineitem_note
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

COMMIT;

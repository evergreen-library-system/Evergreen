BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0161'); -- Scott McKellar

ALTER TABLE acq.lineitem_alert_text
	ADD COLUMN owning_lib INT NOT NULL
	                          REFERENCES actor.org_unit(id)
	                          DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_alert_text
	DROP CONSTRAINT lineitem_alert_text_code_key;

ALTER TABLE acq.lineitem_alert_text
	ADD CONSTRAINT alert_one_code_per_org UNIQUE (code, owning_lib);

COMMIT;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0160'); -- Scott McKellar

CREATE TABLE acq.lineitem_alert_text (
	id               SERIAL         PRIMARY KEY,
	code             TEXT           UNIQUE NOT NULL,
	description      TEXT
);

ALTER TABLE acq.lineitem_note
	ADD COLUMN alert_text    INT     REFERENCES acq.lineitem_alert_text(id)
	                                 DEFERRABLE INITIALLY DEFERRED;

COMMIT;

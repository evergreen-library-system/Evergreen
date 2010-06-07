BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0297'); -- Scott McKellar

ALTER TABLE serial.record_entry
	ALTER COLUMN marc DROP NOT NULL;

CREATE TABLE serial.caption_and_pattern (
	id           SERIAL       PRIMARY KEY,
	record       BIGINT       NOT NULL
	                          REFERENCES serial.record_entry (id)
	                          ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	type         TEXT         NOT NULL
	                          CONSTRAINT cap_type CHECK ( type in
	                          ( 'basic', 'supplement', 'index' )),
	create_time  TIMESTAMPTZ  NOT NULL DEFAULT now(),
	active       BOOL         NOT NULL DEFAULT FALSE,
	pattern_code TEXT         NOT NULL,       -- must contain JSON
	enum_1       TEXT,
	enum_2       TEXT,
	enum_3       TEXT,
	enum_4       TEXT,
	enum_5       TEXT,
	enum_6       TEXT,
	chron_1      TEXT,
	chron_2      TEXT,
	chron_3      TEXT,
	chron_4      TEXT,
	chron_5      TEXT
);

COMMIT;

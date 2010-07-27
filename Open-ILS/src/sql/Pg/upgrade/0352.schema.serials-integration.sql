-- Apply Dan Wells' changes to the serial schema, from the
-- seials-integration branch

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0352'); -- Scott McKellar

CREATE TABLE serial.subscription_note (
	id           SERIAL PRIMARY KEY,
	subscription INT    NOT NULL
	                    REFERENCES serial.subscription (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator      INT    NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
	pub          BOOL   NOT NULL DEFAULT FALSE,
	title        TEXT   NOT NULL,
	value        TEXT   NOT NULL
);

ALTER TABLE serial.caption_and_pattern
RENAME COLUMN create_time TO create_date;

ALTER TABLE serial.distribution
RENAME COLUMN unit_label_base TO unit_label_prefix;

CREATE TABLE serial.distribution_note (
	id           SERIAL PRIMARY KEY,
	distribution INT    NOT NULL
	                    REFERENCES serial.distribution (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator      INT    NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
	pub          BOOL   NOT NULL DEFAULT FALSE,
	title        TEXT   NOT NULL,
	value        TEXT   NOT NULL
);

ALTER TABLE serial.issuance
ADD COLUMN caption_and_pattern   INT   REFERENCES serial.caption_and_pattern (id)
                                       DEFERRABLE INITIALLY DEFERRED;
------- Begin surgery on serial.unit

ALTER TABLE serial.unit
	DROP COLUMN label;

ALTER TABLE serial.unit
	RENAME COLUMN label_sort_key TO sort_key;

ALTER TABLE serial.unit
	RENAME COLUMN contents TO detailed_contents;

ALTER TABLE serial.unit
	ADD COLUMN summary_contents TEXT;

UPDATE serial.unit
SET summary_contents = detailed_contents;

ALTER TABLE serial.unit
	ALTER column summary_contents SET NOT NULL;

------- End surgery on serial.unit

ALTER TABLE serial.item
ADD COLUMN status        TEXT          CONSTRAINT value_status_check CHECK (
                                       status IN ( 'Bindery', 'Bound', 'Claimed', 'Discarded',
                                       'Expected', 'Not Held', 'Not Published', 'Received'))
                                       DEFAULT 'Expected',
ADD COLUMN  shadowed     BOOL          NOT NULL DEFAULT FALSE;

ALTER TABLE serial.bib_summary RENAME TO basic_summary;

ALTER TABLE serial.sup_summary RENAME TO supplement_summary;

COMMIT;

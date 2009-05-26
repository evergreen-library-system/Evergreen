

DROP SCHEMA serial CASCADE;

BEGIN;

CREATE SCHEMA serial;

CREATE TABLE serial.record_entry (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		REFERENCES biblio.record_entry (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	owning_lib	INT		NOT NULL DEFAULT 1 REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	source		INT,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	active		BOOL		NOT NULL DEFAULT TRUE,
	deleted		BOOL		NOT NULL DEFAULT FALSE,
	marc		TEXT		NOT NULL,
	last_xact_id	TEXT		NOT NULL
);
CREATE INDEX serial_record_entry_creator_idx ON serial.record_entry ( creator );
CREATE INDEX serial_record_entry_editor_idx ON serial.record_entry ( editor );
CREATE INDEX serial_record_entry_owning_lib_idx ON serial.record_entry ( owning_lib, deleted );

CREATE TABLE serial.full_rec (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES serial.record_entry(id) DEFERRABLE INITIALLY DEFERRED,
	tag		CHAR(3)		NOT NULL,
	ind1		TEXT,
	ind2		TEXT,
	subfield	TEXT,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE INDEX serial_full_rec_record_idx ON serial.full_rec (record);
CREATE INDEX serial_full_rec_tag_part_idx ON serial.full_rec (SUBSTRING(tag FROM 2));
CREATE TRIGGER serial_full_rec_fti_trigger
	BEFORE UPDATE OR INSERT ON serial.full_rec
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE INDEX serial_full_rec_index_vector_idx ON serial.full_rec USING GIST (index_vector);
/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX serial_full_rec_value_tpo_index ON serial.full_rec (value text_pattern_ops);

CREATE TABLE serial.subscription (
	id		SERIAL	PRIMARY KEY,
	callnumber	BIGINT	REFERENCES asset.call_number (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	uri		INT	REFERENCES asset.uri (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	start_date	DATE	NOT NULL,
	end_date	DATE	-- interpret NULL as current subscription 
);

CREATE TABLE serial.binding_unit (
	id		SERIAL	PRIMARY KEY,
	subscription	INT	NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	label		TEXT	NOT NULL,
	CONSTRAINT bu_label_once_per_sub UNIQUE (subscription, label)
);

CREATE TABLE serial.issuance (
	id		SERIAL	PRIMARY KEY,
	subscription	INT	NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	target_copy	BIGINT	REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	location	BIGINT	REFERENCES asset.copy_location(id) DEFERRABLE INITIALLY DEFERRED,
	binding_unit	INT	REFERENCES serial.binding_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	label		TEXT
);

CREATE TABLE serial.bib_summary (
	id			SERIAL	PRIMARY KEY,
	subscription		INT	UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	generated_coverage	TEXT	NOT NULL,
	textual_holdings	TEXT
);

CREATE TABLE serial.sup_summary (
	id			SERIAL	PRIMARY KEY,
	subscription		INT	UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	generated_coverage	TEXT	NOT NULL,
	textual_holdings	TEXT
);

CREATE TABLE serial.index_summary (
	id			SERIAL	PRIMARY KEY,
	subscription		INT	UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	generated_coverage	TEXT	NOT NULL,
	textual_holdings	TEXT
);

COMMIT;


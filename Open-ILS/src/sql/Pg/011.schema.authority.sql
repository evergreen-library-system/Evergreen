DROP SCHEMA authority CASCADE;

BEGIN;
CREATE SCHEMA authority;

CREATE TABLE authority.record_entry (
	id		BIGSERIAL	PRIMARY KEY,
	arn_source	TEXT		NOT NULL DEFAULT 'AUTOGEN',
	arn_value	TEXT		NOT NULL,
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	active		BOOL		NOT NULL DEFAULT TRUE,
	deleted		BOOL		NOT NULL DEFAULT FALSE,
	source		INT,
	marc		TEXT		NOT NULL,
	last_xact_id	TEXT		NOT NULL
);
CREATE INDEX authority_record_entry_creator_idx ON authority.record_entry ( creator );
CREATE INDEX authority_record_entry_editor_idx ON authority.record_entry ( editor );
CREATE UNIQUE INDEX authority_record_unique_tcn ON authority.record_entry (arn_source,arn_value) WHERE deleted IS FALSE;

CREATE TABLE authority.record_note (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES authority.record_entry (id),
	value		TEXT		NOT NULL,
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now()
);
CREATE INDEX authority_record_note_record_idx ON authority.record_note ( record );
CREATE INDEX authority_record_note_creator_idx ON authority.record_note ( creator );
CREATE INDEX authority_record_note_editor_idx ON authority.record_note ( editor );

CREATE TABLE authority.rec_descriptor (
	id		BIGSERIAL PRIMARY KEY,
	record		BIGINT,
	record_status	"char",
	char_encoding	"char"
);
CREATE INDEX authority_rec_descriptor_record_idx ON authority.rec_descriptor (record);

CREATE TABLE authority.full_rec (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL,
	tag		CHAR(3)		NOT NULL,
	ind1		"char",
	ind2		"char",
	subfield	"char",
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE INDEX authority_full_rec_record_idx ON authority.full_rec (record);
CREATE INDEX authority_full_rec_tag_part_idx ON authority.full_rec (SUBSTRING(tag FROM 2));
CREATE TRIGGER authority_full_rec_fti_trigger
	BEFORE UPDATE OR INSERT ON authority.full_rec
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE INDEX authority_full_rec_index_vector_idx ON authority.full_rec USING GIST (index_vector);

COMMIT;

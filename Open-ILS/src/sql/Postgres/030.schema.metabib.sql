DROP SCHEMA metabib CASCADE;

BEGIN;
CREATE SCHEMA metabib;

CREATE TABLE metabib.metarecord (
	id		BIGSERIAL	PRIMARY KEY,
	fingerprint	TEXT		NOT NULL,
	master_record	BIGINT,
	mods		TEXT		NOT NULL
);
CREATE INDEX metabib_metarecord_master_record_idx ON metabib.metarecord (master_record);

CREATE TABLE metabib.title_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_title_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.title_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.author_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_author_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.author_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.subject_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_subject_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.subject_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.keyword_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_keyword_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.keyword_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.full_rec (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL,
	tag		CHAR(3)		NOT NULL,
	ind1		CHAR(1),
	ind2		CHAR(1),
	subfield	CHAR(1),
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE INDEX metabib_full_rec_record_idx ON metabib.full_rec (record);
CREATE TRIGGER metabib_full_rec_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.full_rec
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE TABLE metabib.title_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT		NOT NULL,
	field_entry	BIGINT		NOT NULL UNIQUE,
	source_record	BIGINT		NOT NULL
);
CREATE INDEX metabib_title_field_entry_source_map_metarecord_idx ON metabib.title_field_entry_source_map (metarecord);
CREATE INDEX metabib_title_field_entry_source_map_source_record_idx ON metabib.title_field_entry_source_map (source_record);

CREATE TABLE metabib.author_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT		NOT NULL,
	field_entry	BIGINT		NOT NULL UNIQUE,
	source_record	BIGINT		NOT NULL
);
CREATE INDEX metabib_author_field_entry_source_map_metarecord_idx ON metabib.author_field_entry_source_map (metarecord);
CREATE INDEX metabib_author_field_entry_source_map_source_record_idx ON metabib.author_field_entry_source_map (metarecord);

CREATE TABLE metabib.subject_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT		NOT NULL,
	field_entry	BIGINT		NOT NULL UNIQUE,
	source_record	BIGINT		NOT NULL
);
CREATE INDEX metabib_subject_field_entry_source_map_metarecord_idx ON metabib.subject_field_entry_source_map (metarecord);
CREATE INDEX metabib_subject_field_entry_source_map_source_record_idx ON metabib.subject_field_entry_source_map (metarecord);

CREATE TABLE metabib.keyword_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT		NOT NULL,
	field_entry	BIGINT		NOT NULL UNIQUE,
	source_record	BIGINT		NOT NULL
);
CREATE INDEX metabib_keyword_field_entry_source_map_metarecord_idx ON metabib.keyword_field_entry_source_map (metarecord);
CREATE INDEX metabib_keyword_field_entry_source_map_source_record_idx ON metabib.keyword_field_entry_source_map (source_record);

COMMIT;

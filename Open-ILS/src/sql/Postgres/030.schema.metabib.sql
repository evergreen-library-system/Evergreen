DROP SCHEMA metabib CASCADE;

BEGIN;
CREATE SCHEMA metabib;

CREATE TABLE metabib.metarecord (
	id		BIGSERIAL	PRIMARY KEY,
	fingerprint	TEXT		NOT NULL,
	master_record	BIGINT		REFERENCES biblio.record_entry (id)
);

CREATE TABLE metabib.title_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL REFERENCES config.metabib_field_map (id),
--	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
--CREATE TRIGGER metabib_title_field_entry_fti_trigger
--	BEFORE UPDATE OR INSERT ON metabib.title_field_entry
--	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.author_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL REFERENCES config.metabib_field_map (id),
--	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
--CREATE TRIGGER metabib_author_field_entry_fti_trigger
--	BEFORE UPDATE OR INSERT ON metabib.author_field_entry
--	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.subject_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL REFERENCES config.metabib_field_map (id),
--	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
--CREATE TRIGGER metabib_subject_field_entry_fti_trigger
--	BEFORE UPDATE OR INSERT ON metabib.subject_field_entry
--	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.keyword_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL REFERENCES config.metabib_field_map (id),
--	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
--CREATE TRIGGER metabib_keyword_field_entry_fti_trigger
--	BEFORE UPDATE OR INSERT ON metabib.keyword_field_entry
--	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.full_rec (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES biblio.record_entry (id),
	tag		CHAR(3)		NOT NULL,
	subfield	CHAR(1),
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_full_rec_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.full_rec
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE VIEW metabib.tag_level_full_rec AS
	SELECT	record,
		tag,
		agg_text(value) AS value
		agg_tsvector(index_vector) AS index_vector
	  FROM	metabib.full_rec
	  GROUP BY 1, 2;

CREATE TABLE metabib.title_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	field_entry	BIGINT		NOT NULL REFERENCES metabib.title_field_entry (id) ON DELETE CASCADE,
	source_record	BIGINT		NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE
);

CREATE TABLE metabib.author_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	field_entry	BIGINT		NOT NULL REFERENCES metabib.author_field_entry (id) ON DELETE CASCADE,
	source_record	BIGINT		NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE
);

CREATE TABLE metabib.subject_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	field_entry	BIGINT		NOT NULL REFERENCES metabib.subject_field_entry (id) ON DELETE CASCADE,
	source_record	BIGINT		NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE
);

CREATE TABLE metabib.keyword_field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	field_entry	BIGINT		NOT NULL REFERENCES metabib.keyword_field_entry (id) ON DELETE CASCADE,
	source_record	BIGINT		NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE
);

COMMIT;

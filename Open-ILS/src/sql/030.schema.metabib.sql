DROP SCHEMA metabib CASCADE;

BEGIN;
CREATE SCHEMA metabib;

CREATE TABLE metabib.metarecord (
	id		BIGSERIAL	PRIMARY KEY,
	fingerprint	TEXT		NOT NULL,
	master_record	BIGINT		REFERENCES biblio.record_entry (id)
);

CREATE TABLE metabib.field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	field		INT		NOT NULL REFERENCES config.metabib_field_map,
	field_class	INT		NOT NULL REFERENCES config.metabib_field_class_map,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);

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

CREATE TABLE metabib.field_entry_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	field_entry	BIGINT		NOT NULL REFERENCES metabib.field_entry (id),
	source_record	BIGINT		NOT NULL REFERENCES biblio.record_entry (id)
);

COMMIT;

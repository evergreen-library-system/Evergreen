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
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_title_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.title_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.author_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_author_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.author_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.subject_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_subject_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.subject_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);


CREATE TABLE metabib.keyword_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_keyword_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.keyword_field_entry
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE TABLE metabib.rec_descriptor (
	id		BIGSERIAL PRIMARY KEY,
	record		BIGINT,
	item_type	TEXT,
	item_form	TEXT,
	bib_level	TEXT,
	control_type	TEXT,
	char_encoding	TEXT,
	enc_level	TEXT,
	cat_form	TEXT,
	pub_status	TEXT,
	item_lang	TEXT,
	audience	TEXT
);
/* We may not need these...

CREATE INDEX metabib_rec_descriptor_item_type_idx ON metabib.rec_descriptor (item_type);
CREATE INDEX metabib_rec_descriptor_item_form_idx ON metabib.rec_descriptor (item_form);
CREATE INDEX metabib_rec_descriptor_bib_level_idx ON metabib.rec_descriptor (bib_level);
CREATE INDEX metabib_rec_descriptor_control_type_idx ON metabib.rec_descriptor (control_type);
CREATE INDEX metabib_rec_descriptor_char_encoding_idx ON metabib.rec_descriptor (char_encoding);
CREATE INDEX metabib_rec_descriptor_enc_level_idx ON metabib.rec_descriptor (enc_level);
CREATE INDEX metabib_rec_descriptor_cat_form_idx ON metabib.rec_descriptor (cat_form);
CREATE INDEX metabib_rec_descriptor_pub_status_idx ON metabib.rec_descriptor (pub_status);
CREATE INDEX metabib_rec_descriptor_item_lang_idx ON metabib.rec_descriptor (item_lang);
CREATE INDEX metabib_rec_descriptor_audience_idx ON metabib.rec_descriptor (audience);

*/


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

-- CREATE TABLE metabib.title_field_entry_source_map (
	-- id		BIGSERIAL	PRIMARY KEY,
	-- field_entry	BIGINT		NOT NULL,
	-- metarecord	BIGINT		NOT NULL,
	-- source_record	BIGINT		NOT NULL
-- );
-- CREATE INDEX metabib_title_field_entry_source_map_source_record_idx ON metabib.title_field_entry_source_map (source_record);
-- CREATE INDEX metabib_title_field_entry_source_map_field_entry_idx ON metabib.title_field_entry_source_map (field_entry);

-- CREATE TABLE metabib.author_field_entry_source_map (
	-- id		BIGSERIAL	PRIMARY KEY,
	-- field_entry	BIGINT		NOT NULL,
	-- metarecord	BIGINT		NOT NULL,
	-- source_record	BIGINT		NOT NULL
-- );
-- CREATE INDEX metabib_author_field_entry_source_map_source_record_idx ON metabib.author_field_entry_source_map (source_record);
-- CREATE INDEX metabib_author_field_entry_source_map_field_entry_idx ON metabib.author_field_entry_source_map (field_entry);

-- CREATE TABLE metabib.subject_field_entry_source_map (
	-- id		BIGSERIAL	PRIMARY KEY,
	-- field_entry	BIGINT		NOT NULL,
	-- metarecord	BIGINT		NOT NULL,
	-- source_record	BIGINT		NOT NULL
-- );
-- CREATE INDEX metabib_subject_field_entry_source_map_source_record_idx ON metabib.subject_field_entry_source_map (source_record);
-- CREATE INDEX metabib_subject_field_entry_source_map_field_entry_idx ON metabib.subject_field_entry_source_map (field_entry);

-- CREATE TABLE metabib.keyword_field_entry_source_map (
	-- id		BIGSERIAL	PRIMARY KEY,
	-- field_entry	BIGINT		NOT NULL,
	-- metarecord	BIGINT		NOT NULL,
	-- source_record	BIGINT		NOT NULL
-- );
-- CREATE INDEX metabib_keyword_field_entry_source_map_source_record_idx ON metabib.keyword_field_entry_source_map (source_record);
-- CREATE INDEX metabib_keyword_field_entry_source_map_field_entry_idx ON metabib.keyword_field_entry_source_map (field_entry);

CREATE TABLE metabib.metarecord_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT		NOT NULL,
	source		BIGINT		NOT NULL
);
CREATE INDEX metabib_metarecord_source_map_metarecord_idx ON metabib.metarecord_source_map (metarecord);
CREATE INDEX metabib_metarecord_source_map_source_record_idx ON metabib.metarecord_source_map (source);


COMMIT;

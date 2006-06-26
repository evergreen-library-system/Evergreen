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
	record_status	TEXT,
	char_encoding	TEXT
);
CREATE INDEX authority_rec_descriptor_record_idx ON authority.rec_descriptor (record);

CREATE TABLE authority.full_rec (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL,
	tag		CHAR(3)		NOT NULL,
	ind1		TEXT,
	ind2		TEXT,
	subfield	TEXT,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE INDEX authority_full_rec_record_idx ON authority.full_rec (record);
CREATE INDEX authority_full_rec_tag_part_idx ON authority.full_rec (SUBSTRING(tag FROM 2));
CREATE TRIGGER authority_full_rec_fti_trigger
	BEFORE UPDATE OR INSERT ON authority.full_rec
	FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE INDEX authority_full_rec_index_vector_idx ON authority.full_rec USING GIST (index_vector);

CREATE OR REPLACE VIEW authority.tracing_links AS
	SELECT	main.record AS record,
		main.id AS main_id,
		main.tag AS main_tag,
		main.value AS main_value,
		substr(link.value,1,1) AS relationship,
		substr(link.value,2,1) AS use_restriction,
		substr(link.value,3,1) AS deprecation,
		substr(link.value,4,1) AS display_restriction,
		link_value.id AS link_id,
		link_value.tag AS link_tag,
		link_value.value AS link_value
	  FROM	authority.full_rec main
		JOIN authority.full_rec link
			ON (	link.record = main.record
				AND link.tag in ((main.tag::int + 400)::text, (main.tag::int + 300)::text)
				AND link.subfield = 'w' )
		JOIN authority.full_rec link_value
			ON (	link_value.record = main.record
				AND link_value.tag = link.tag
				AND link_value.subfield = 'a' )
	  WHERE	main.tag IN ('100','110','111','130','150','151','155','180','181','182','185')
		AND main.subfield = 'a';


COMMIT;

DROP SCHEMA biblio CASCADE;

BEGIN;
CREATE SCHEMA biblio;

CREATE SEQUENCE biblio.autogen_tcn_value_seq;
CREATE FUNCTION biblio.next_autogen_tcn_value () RETURNS TEXT AS $$
	BEGIN RETURN nextval('biblio.autogen_tcn_value_seq'::TEXT); END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE biblio.record_entry (
	id		BIGSERIAL	PRIMARY KEY,
	tcn_source	TEXT		NOT NULL DEFAULT 'AUTOGEN',
	tcn_value	TEXT		NOT NULL DEFAULT biblio.next_autogen_tcn_value(),
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	create_date	TIMESTAMP	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP	NOT NULL DEFAULT now(),
	active		BOOL		NOT NULL DEFAULT TRUE,
	deleted		BOOL		NOT NULL DEFAULT FALSE,
	source		INT,
	last_xact_id	TEXT		NOT NULL DEFAULT 'none'
);
CREATE INDEX biblio_record_entry_creator_idx ON biblio.record_note ( creator );
CREATE INDEX biblio_record_entry_editor_idx ON biblio.record_note ( editor );
CREATE UNIQUE INDEX biblio_record_unique_tcn ON (tcn_source,tcn_value) WHERE deleted IS FALSE;

CREATE TABLE biblio.record_mods (
	id	BIGINT	PRIMARY KEY,
	mods	TEXT	NOT NULL
)

CREATE TABLE biblio.record_data (
	id		BIGSERIAL	PRIMARY KEY,
	owner_doc	BIGINT		NOT NULL,
	intra_doc_id	INT		NOT NULL,
	parent_node	INT,
	node_type	INT		NOT NULL,
	namespace_uri	TEXT,
	name		TEXT,
	value		TEXT,
	last_xact_id	TEXT		NOT NULL DEFAULT 'none',
	CONSTRAINT unique_doc_and_id UNIQUE (owner_doc,intra_doc_id)
);

CREATE TABLE biblio.record_note (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL,
	value		TEXT		NOT NULL,
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	create_date	TIMESTAMP	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP	NOT NULL DEFAULT now()
);
CREATE INDEX biblio_record_note_record_idx ON biblio.record_note ( record );
CREATE INDEX biblio_record_note_creator_idx ON biblio.record_note ( creator );
CREATE INDEX biblio_record_note_editor_idx ON biblio.record_note ( editor );

COMMIT;

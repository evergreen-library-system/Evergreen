DROP SCHEMA biblio CASCADE;

BEGIN;
CREATE SCHEMA biblio;

CREATE SEQUENCE biblio.autogen_tcn_value_seq;
CREATE FUNCTION biblio.next_autogen_tcn_value () RETURNS TEXT AS $$
	BEGIN RETURN nextval('biblio.autogen_tcn_value_seq'::TEXT); END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE biblio.record_entry (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT, -- add FKEY for metabib.metarecord
	tcn_source	TEXT		NOT NULL DEFAULT 'AUTOGEN',
	tcn_value	TEXT		NOT NULL DEFAULT biblio.next_autogen_tcn_value(),
	creator		INT		NOT NULL DEFAULT 1 REFERENCES actor.usr (id),
	editor		INT		NOT NULL DEFAULT 1 REFERENCES actor.usr (id),
	create_date	TIMESTAMP	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP	NOT NULL DEFAULT now(),
	active		BOOL		NOT NULL DEFAULT TRUE,
	deleted		BOOL		NOT NULL DEFAULT FALSE,
	CONSTRAINT unique_tcn UNIQUE (tcn_source,tcn_value)
);

CREATE TABLE biblio.record_data (
	id		BIGSERIAL	PRIMARY KEY,
	owner_doc	BIGINT		NOT NULL REFERENCES biblio.record_entry (id) ON UPDATE RESTRICT ON DELETE CASCADE,
	intra_doc_id	INT		NOT NULL,
	parent_node	INT,
	node_type	INT		NOT NULL,
	namespace_uri	TEXT,
	name		TEXT,
	value		TEXT,
	CONSTRAINT unique_doc_and_id UNIQUE (owner_doc,intra_doc_id),
	CONSTRAINT local_fkey FOREIGN KEY ( owner_doc, parent_node )
		REFERENCES biblio.record_data ( owner_doc, intra_doc_id ) ON DELETE CASCADE
);

CREATE TABLE biblio.record_note (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES biblio.record_entry (id),
	value		TEXT		NOT NULL,
	creator		INT		NOT NULL DEFAULT 1 REFERENCES actor.usr (id),
	editor		INT		NOT NULL DEFAULT 1 REFERENCES actor.usr (id),
	create_date	TIMESTAMP	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP	NOT NULL DEFAULT now()
);

COMMIT;

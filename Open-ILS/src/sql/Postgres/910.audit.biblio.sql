CREATE SCHEMA audit;

BEGIN;

CREATE TABLE audit.biblio_record_entry (
	id		BIGINT				NOT NULL
	tcn_source	TEXT				NOT NULL,
	tcn_value	TEXT				NOT NULL,
	creator		INT				NOT NULL,
	editor		INT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL,
	edit_date	TIMESTAMP WITH TIME ZONE	NOT NULL,
	active		BOOL				NOT NULL,
	deleted		BOOL				NOT NULL,
	source		INT,
	last_xact_id	TEXT				NOT NULL,
	deleted		BOOL				NOT NULL DEFAULT FALSE,
) WITHOUT OIDS;

CREATE TABLE audit.biblio_record_data (
	id		BIGINT		NOT NULL,
	owner_doc	BIGINT		NOT NULL,
	intra_doc_id	INT		NOT NULL,
	parent_node	INT,
	node_type	INT		NOT NULL,
	namespace_uri	TEXT,
	name		TEXT,
	value		TEXT,
	last_xact_id	TEXT		NOT NULL
);

COMMIT;

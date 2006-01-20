DROP SCHEMA biblio CASCADE;

BEGIN;
CREATE SCHEMA biblio;

CREATE SEQUENCE biblio.autogen_tcn_value_seq;
CREATE FUNCTION biblio.next_autogen_tcn_value () RETURNS TEXT AS $$
	BEGIN RETURN nextval('biblio.autogen_tcn_value_seq'::TEXT); END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE biblio.record_entry (
	id		BIGSERIAL	PRIMARY KEY,
	fingerprint	TEXT,
	tcn_source	TEXT		NOT NULL DEFAULT 'AUTOGEN',
	tcn_value	TEXT		NOT NULL DEFAULT biblio.next_autogen_tcn_value(),
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
CREATE INDEX biblio_record_entry_creator_idx ON biblio.record_entry ( creator );
CREATE INDEX biblio_record_entry_editor_idx ON biblio.record_entry ( editor );
CREATE UNIQUE INDEX biblio_record_unique_tcn ON biblio.record_entry (tcn_source,tcn_value) WHERE deleted IS FALSE;

CREATE TABLE biblio.record_note (
	id		BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL,
	value		TEXT		NOT NULL,
	creator		INT		NOT NULL DEFAULT 1,
	editor		INT		NOT NULL DEFAULT 1,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	edit_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now()
);
CREATE INDEX biblio_record_note_record_idx ON biblio.record_note ( record );
CREATE INDEX biblio_record_note_creator_idx ON biblio.record_note ( creator );
CREATE INDEX biblio_record_note_editor_idx ON biblio.record_note ( editor );

INSERT INTO biblio.record_entry VALUES (-1,'','AUTOGEN','-1',1,1,NOW(),NOW(),FALSE,FALSE,1,'','FOO');

COMMIT;

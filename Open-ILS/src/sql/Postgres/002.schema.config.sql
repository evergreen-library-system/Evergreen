DROP SCHEMA config CASCADE;

BEGIN;
CREATE SCHEMA config;

CREATE TABLE config.bib_source (
	id	SERIAL	PRIMARY KEY,
	quality	INT	CHECK ( quality BETWEEN 0 AND 100 ),
	source	TEXT	NOT NULL UNIQUE
);

INSERT INTO config.bib_source (quality, source)
	VALUES (90, 'OcLC');

INSERT INTO config.bib_source (quality, source)
	VALUES (10, 'System Local');

CREATE TABLE config.metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	CHECK (lower(field_class) IN ('title','author','subject','keyword')),
	name		TEXT	UNIQUE NOT NULL,
	xpath		TEXT	NOT NULL
);

COMMIT;

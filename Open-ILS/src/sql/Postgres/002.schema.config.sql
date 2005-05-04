DROP SCHEMA config CASCADE;

BEGIN;
CREATE SCHEMA config;

CREATE TABLE config.bib_source (
	id	SERIAL	PRIMARY KEY,
	quality	INT	CHECK ( quality BETWEEN 0 AND 100 ),
	source	TEXT	NOT NULL UNIQUE
);

INSERT INTO config.bib_source (quality, source) VALUES (90, 'OcLC');
INSERT INTO config.bib_source (quality, source) VALUES (10, 'System Local');

CREATE TABLE config.standing (
	id		SERIAL	PRIMARY KEY,
	value		TEXT	NOT NULL UNIQUE
);

INSERT INTO config.standing (value) VALUES ('Good');
INSERT INTO config.standing (value) VALUES ('Barred');
INSERT INTO config.standing (value) VALUES ('Blocked');

CREATE TABLE config.metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	NOT NULL CHECK (lower(field_class) IN ('title','author','subject','keyword')),
	name		TEXT	NOT NULL UNIQUE,
	xpath		TEXT	NOT NULL
);

INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'abbreviated', $$//mods:mods/mods:titleInfo[mods:title and (@type='abreviated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'translated', $$//mods:mods/mods:titleInfo[mods:title and (@type='translated')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'uniform', $$//mods:mods/mods:titleInfo[mods:title and (@type='uniform')]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'title', 'proper', $$//mods:mods/mods:titleInfo[mods:title and not (@type)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'corporate', $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'personal', $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'conference', $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:text[text()='creator']]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'author', 'other', $$//mods:mods/mods:name[@type='personal']/mods:namePart[not(../mods:role)]$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'geographic', $$//mods:mods/mods:subject/mods:geographic$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'name', $$//mods:mods/mods:subject/mods:name$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'temporal', $$//mods:mods/mods:subject/mods:temporal$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'topic', $$//mods:mods/mods:subject/mods:topic$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'subject', 'genre', $$//mods:mods/mods:genre$$ );
INSERT INTO config.metabib_field ( field_class, name, xpath ) VALUES ( 'keyword', 'keyword', $$//mods:mods/*[not(local-name()='originInfo')]$$ ); -- /* to fool vim */

CREATE TABLE config.identification_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE
);

INSERT INTO config.identification_type ( name ) VALUES ( 'Drivers Licence' );
INSERT INTO config.identification_type ( name ) VALUES ( 'Voter Card' );
INSERT INTO config.identification_type ( name ) VALUES ( 'Two Utility Bills' );
INSERT INTO config.identification_type ( name ) VALUES ( 'State ID' );
INSERT INTO config.identification_type ( name ) VALUES ( 'SSN' );

CREATE TABLE config.rule_circ_duration (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	extended	INTERVAL	NOT NULL,
	normal		INTERVAL	NOT NULL,
	shrt		INTERVAL	NOT NULL,
	max_renewals	INT		NOT NULL
);

CREATE TABLE config.rule_max_fine (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	amount	NUMERIC(6,2)	NOT NULL
);

CREATE TABLE config.rule_recuring_fine (
	id			SERIAL		PRIMARY KEY,
	name			TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	high			NUMERIC(6,2)	NOT NULL,
	normal			NUMERIC(6,2)	NOT NULL,
	low			NUMERIC(6,2)	NOT NULL,
	recurance_interval	INTERVAL	NOT NULL DEFAULT '1 day'::INTERVAL
);

CREATE TABLE config.rule_age_hold_protect (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ '^\\w+$' ),
	age	INTERVAL	NOT NULL,
	radius	INT		NOT NULL
);

CREATE TABLE config.copy_status (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE
);
INSERT INTO config.copy_status (id,name) VALUES (0,'Available');
INSERT INTO config.copy_status (name) VALUES ('Checked out');
INSERT INTO config.copy_status (name) VALUES ('Bindery');
INSERT INTO config.copy_status (name) VALUES ('Lost');
INSERT INTO config.copy_status (name) VALUES ('Missing');
INSERT INTO config.copy_status (name) VALUES ('In process');
INSERT INTO config.copy_status (name) VALUES ('In transit');
INSERT INTO config.copy_status (name) VALUES ('Reshelving');
INSERT INTO config.copy_status (name) VALUES ('On holds shelf');
INSERT INTO config.copy_status (name) VALUES ('On order');
INSERT INTO config.copy_status (name) VALUES ('ILL');
INSERT INTO config.copy_status (name) VALUES ('Cataloging');
INSERT INTO config.copy_status (name) VALUES ('Reserves');
INSERT INTO config.copy_status (name) VALUES ('Discard/Weed');

SELECT SETVAL('config.copy_status_id_seq'::TEXT, 100);


CREATE TABLE config.net_access_level (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE
);
INSERT INTO config.net_access_level (name) VALUES ('Restricted');
INSERT INTO config.net_access_level (name) VALUES ('Full');
INSERT INTO config.net_access_level (name) VALUES ('None');

COMMIT;


DROP SCHEMA serials CASCADE;

BEGIN;

CREATE SCHEMA serials;

CREATE TABLE serials.serial (
	id		SERIAL				PRIMARY KEY,
	creator		INT				NOT NULL REFERENCES actor.usr (id),
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
	record		BIGINT				REFERENCES biblio.record_entry (id),
	marc		TEXT				NOT NULL,
	language	TEXT				NOT NULL REFERENCES config.language_map (code) DEFAULT 'eng',
	cn_label	TEXT				NOT NULL
);

CREATE TABLE serials.picklist_entry_attr (
	id		BIGSERIAL	PRIMARY KEY,
	serial		BIGINT		NOT NULL REFERENCES serials.serial (id) ON DELETE CASCADE,
	attr_type	TEXT		NOT NULL,
	attr_name	TEXT		NOT NULL,
	attr_value	TEXT		NOT NULL
);


CREATE TABLE serials.subscription (
	id		SERIAL				PRIMARY KEY,
	serial		BIGINT				NOT NULL REFERENCES serials.serial (id) ON DELETE CASCADE,
	creator		INT				NOT NULL REFERENCES actor.usr (id),
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	owner		INT				NOT NULL REFERENCES actor.org_unit (id),
	claim_interval	INTERVAL			NOT NULL DEFAULT '1 month'
);

CREATE TABLE serials.chronology (
	id		SERIAL				PRIMARY KEY,
	creator		INT				NOT NULL REFERENCES actor.usr (id),
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
	subscription	INT				NOT NULL REFERENCES serials.subscription (id)
);

CREATE TABLE serials.enumeration_caption (
	id	SERIAL	PRIMARY KEY,
	name	TEXT	NOT NULL UNIQUE,
	value	TEXT
);

INSERT INTO serials.enumeration_caption (name,value) VALUES ('Abteilung','Abt.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('number,-s','no.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('Band','Bd.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('numero (French)','no');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('book','bk.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('numero (Italian)','n.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('deel','d.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('Nummer','Nr.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('edition','ed.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('nummer','nr.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('editions','eds.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('page, pages','p.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('facsimile','facsim.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('part','pt.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('facsimiles','facsims.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('parts','pts.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('fascicle','fasc.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('partie','ptie');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('Jahrgang','Jahrg.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('parties','pties');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('Lieferung','Lfg.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('series','ser.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('neue Folge','n.F.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('supplement','suppl.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('new series','n.s.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('Teil, Theil','T.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('nouveau','nouv.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('tome','t.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('nouvelle','nouv.');
INSERT INTO serials.enumeration_caption (name,value) VALUES ('volume,-s','v.');


CREATE TABLE serials.enumeration_transformation (
	id		SERIAL	PRIMARY KEY,
	transform	TEXT	NOT NULL


CREATE TABLE serials.enumeration (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE,
	caption		INT		NOT NULL REFERENCES serials.enumeration_caption (id),
	transform	INT		NOT NULL REFERENCES serials.enumeration_transformation (id),
	extent		INT		NOT NULL,
	compress	BOOL		NOT NULL DEFAULT FALSE
);

CREATE TABLE serials.cycle (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE,
	cycle_interval	INTERVAL	NOT NULL,
	enumeration	INT		NOT NULL REFERENCES serials.enumeration (id),
	display_year	BOOL		NOT NULL DEFAULT FALSE,
	display_month	BOOL		NOT NULL DEFAULT FALSE,
	display_date	BOOL		NOT NULL DEFAULT FALSE
);

CREATE TABLE serials.chrono_segment (
	id		SERIAL		PRIMARY KEY,
	cycle		INT		NOT NULL REFERENCES serials.cycle (id),
	start		DATE		NOT NULL,
	length		INTERVAL	NOT NULL,
	redaction	BOOL		NOT NULL DEFAULT FALSE
);

CREATE TABLE serials.chronology_projection (
	id		SERIAL	PRIMARY KEY,
	subscription	INT	NOT NULL REFERENCES serials.subscription (id),
	when		DATE	NOT NULL,



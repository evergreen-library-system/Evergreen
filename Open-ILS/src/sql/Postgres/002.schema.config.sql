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
	field_class	TEXT	NOT NULL CHECK (lower(field_class) IN ('title','author','subject','keyword')),
	name		TEXT	NOT NULL UNIQUE,
	xpath		TEXT	NOT NULL
);

CREATE TABLE config.item_type_map (
	typeid		TEXT	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE
);

INSERT INTO config.item_type_map (typeid,name) VALUES ('a','Language material');
INSERT INTO config.item_type_map (typeid,name) VALUES ('c','Notated music');
INSERT INTO config.item_type_map (typeid,name) VALUES ('d','Manuscript notated music');
INSERT INTO config.item_type_map (typeid,name) VALUES ('e','Cartographic material');
INSERT INTO config.item_type_map (typeid,name) VALUES ('f','Manuscript cartographic material');
INSERT INTO config.item_type_map (typeid,name) VALUES ('g','Projected medium');
INSERT INTO config.item_type_map (typeid,name) VALUES ('i','Nonmusical sound recording');
INSERT INTO config.item_type_map (typeid,name) VALUES ('j','Musical sound recording');
INSERT INTO config.item_type_map (typeid,name) VALUES ('k','Two-dimensional nonprojectable graphic');
INSERT INTO config.item_type_map (typeid,name) VALUES ('m','Computer file');
INSERT INTO config.item_type_map (typeid,name) VALUES ('o','Kit');
INSERT INTO config.item_type_map (typeid,name) VALUES ('p','Mixed material');
INSERT INTO config.item_type_map (typeid,name) VALUES ('r','Three-dimensional artifact or naturally occurring object');
INSERT INTO config.item_type_map (typeid,name) VALUES ('t','Manuscript language material');


COMMIT;

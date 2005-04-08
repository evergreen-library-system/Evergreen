DROP SCHEMA actor CASCADE;

BEGIN;
CREATE SCHEMA actor;

CREATE TABLE actor.usr (
	id			SERIAL		PRIMARY KEY,
	card			INT		UNIQUE, -- active card
	usrid			TEXT		NOT NULL UNIQUE,
	usrname			TEXT		NOT NULL UNIQUE,
	email			TEXT		CHECK (email ~ $re$^[[:alnum:]_\.]+@[[:alnum:]_]+(?:\.[[:alnum:]_])+$$re$),
	passwd			TEXT		NOT NULL,
	prefix			TEXT,
	first_given_name	TEXT		NOT NULL,
	second_given_name	TEXT,
	family_name		TEXT		NOT NULL,
	suffix			TEXT,
	address			INT,
	home_ou			INT,
	gender			CHAR(1) 	NOT NULL CHECK ( LOWER(gender) IN ('m','f') ),
	dob			DATE		NOT NULL,
	active			BOOL		NOT NULL DEFAULT TRUE,
	master_account		BOOL		NOT NULL DEFAULT FALSE,
	super_user		BOOL		NOT NULL DEFAULT FALSE,
	usrgroup		SERIAL		NOT NULL,
	claims_returned_count	INT		NOT NULL DEFAULT 0,
	credit_forward_balance	NUMERIC(6,2)	NOT NULL DEFAULT 0.00,
	last_xact_id		TEXT		NOT NULL DEFAULT 'none'

);
CREATE INDEX actor_usr_home_ou_idx ON actor.usr (home_ou);
CREATE INDEX actor_usr_address_idx ON actor.usr (address);

CREATE FUNCTION actor.crypt_pw_insert () RETURNS TRIGGER AS $$
	BEGIN
		NEW.passwd = MD5( NEW.passwd );
		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION actor.crypt_pw_update () RETURNS TRIGGER AS $$
	BEGIN
		IF NEW.passwd <> OLD.passwd THEN
			NEW.passwd = MD5( NEW.passwd );
		END IF;
		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER actor_crypt_pw_update_trigger
	BEFORE UPDATE ON actor.usr FOR EACH ROW
	EXECUTE PROCEDURE actor.crypt_pw_update ();

CREATE TRIGGER actor_crypt_pw_insert_trigger
	BEFORE INSERT ON actor.usr FOR EACH ROW
	EXECUTE PROCEDURE actor.crypt_pw_insert ();

-- Just so that there is a user...
INSERT INTO actor.usr ( card, usrid, usrname, passwd, first_given_name, family_name, gender, dob, master_account, super_user )
	VALUES ( 1,'admin', 'admin', 'open-ils', 'Administrator', '', 'm', '1979-01-22', TRUE, TRUE );

CREATE TABLE actor.stat_cat (
	id		SERIAL  PRIMARY KEY,
	owner		INT     NOT NULL, -- actor.org_unit.id
	name		TEXT    NOT NULL,
	opac_visible	BOOL NOT NULL DEFAULT FALSE,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE actor.stat_cat_entry (
	id	SERIAL  PRIMARY KEY,
	owner	INT     NOT NULL, -- actor.org_unit.id
	value	TEXT    NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (owner,value)
);

CREATE TABLE actor.stat_cat_entry_usr_map (
	id		BIGSERIAL       PRIMARY KEY,
	stat_cat_entry	INT             NOT NULL, -- needs ON DELETE CASCADE
	target_usr	BIGINT          NOT NULL, -- needs ON DELETE CASCADE
	CONSTRAINT sce_once_per_copy UNIQUE (target_usr,stat_cat_entry)
);

CREATE TABLE actor.card (
	id	SERIAL	PRIMARY KEY,
	usr	INT,
	barcode	TEXT	NOT NULL UNIQUE,
	active	BOOL	NOT NULL DEFAULT TRUE
);
CREATE INDEX actor_card_usr_idx ON actor.card (usr);

INSERT INTO actor.card (usr, barcode) VALUES (1,'101010101010101');


CREATE TABLE actor.org_unit_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	depth		INT	NOT NULL,
	parent		INT,
	can_have_vols	BOOL	NOT NULL DEFAULT TRUE,
	can_have_users	BOOL	NOT NULL DEFAULT TRUE
);

-- The PINES levels
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users, can_have_vols) VALUES ( 'Consortium', 0, NULL, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users, can_have_vols) VALUES ( 'System', 1, 1, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, depth, parent) VALUES ( 'Branch', 2, 2 );
INSERT INTO actor.org_unit_type (name, depth, parent) VALUES ( 'Sub-lib', 5, 3 );

CREATE TABLE actor.org_unit (
	id		SERIAL	PRIMARY KEY,
	parent_ou	INT,
	ou_type		INT	NOT NULL,
	address		INT,
	shortname	TEXT	NOT NULL,
	name		TEXT
);
CREATE INDEX actor_org_unit_parent_ou_idx ON actor.org_unit (parent_ou);
CREATE INDEX actor_org_unit_ou_type_idx ON actor.org_unit (ou_type);
CREATE INDEX actor_org_unit_address_idx ON actor.org_unit (address);

INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (NULL, 1, 'PINES', 'Georgia PINES Consortium');


-- Some PINES test libraries
-- XXX use lib_splitter.pl to do this
-- 
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 2, 'ARL', 'Athens Regional Library System');
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 3, 'ARL-ATH', 'Athens-Clark County Library');
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 3, 'ARL-BOG', 'Bogart Branch Library');
-- 
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 2, 'MGRL', 'Middle Georgia Regional Library System');
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 3, 'MGRL-RC', 'Rocky Creek Branch Library');
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 3, 'MGRL-WA', 'Washington Memorial Library');
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 4, 'MGRL-MM', 'Bookmobile');
-- 
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 2, 'HOU', 'Houston County Library System');
-- INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (currval('actor.org_unit_id_seq'::TEXT), 3, 'HOU-WR', 'Nola Brantley Memorial Library');

CREATE TABLE actor.usr_access_entry (
	id		BIGSERIAL	PRIMARY KEY,
	usr		INT,
	org_unit	INT,
	CONSTRAINT usr_once_per_ou UNIQUE (usr,org_unit)
);


CREATE TABLE actor.perm_group (
	id	SERIAL	PRIMARY KEY,
	name	TEXT	NOT NULL,
	ou_type	INT
);

CREATE TABLE actor.permission (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	code		TEXT	NOT NULL UNIQUE
);

CREATE TABLE actor.perm_group_permission_map (
	permission	INT,
	perm_group	INT,
	CONSTRAINT perm_once_per_group PRIMARY KEY (permission, perm_group)
);

CREATE TABLE actor.perm_group_usr_map (
	usr		INT,
	perm_group	INT,
	CONSTRAINT usr_once_per_group PRIMARY KEY (usr, perm_group)
);

CREATE TABLE actor.usr_address (
	id		SERIAL	PRIMARY KEY,
	valid		BOOL	NOT NULL DEFAULT TRUE,
	usr		INT,
	street1		TEXT	NOT NULL,
	street2		TEXT,
	county		TEXT	NOT NULL,
	state		TEXT	NOT NULL,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL
);

COMMIT;

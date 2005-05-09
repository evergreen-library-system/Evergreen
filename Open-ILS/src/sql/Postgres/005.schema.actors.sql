DROP SCHEMA actor CASCADE;

BEGIN;
CREATE SCHEMA actor;

CREATE TABLE actor.usr (
	id			SERIAL		PRIMARY KEY,
	card			INT		UNIQUE, -- active card
	profile			INT		NOT NULL, -- patron profile
	usrname			TEXT		NOT NULL UNIQUE,
	email			TEXT,
	passwd			TEXT		NOT NULL,
	standing		INT		NOT NULL DEFAULT 1 REFERENCES config.standing (id),
	ident_type		INT		NOT NULL REFERENCES config.identification_type (id),
	ident_value		TEXT		NOT NULL,
	ident_type2		INT		REFERENCES config.identification_type (id),
	ident_value2		TEXT,
	net_access_level	INT		NOT NULL DEFAULT 1 REFERENCES config.net_access_level (id),
	photo_url		TEXT,
	prefix			TEXT,
	first_given_name	TEXT		NOT NULL,
	second_given_name	TEXT,
	family_name		TEXT		NOT NULL,
	suffix			TEXT,
	day_phone		TEXT,
	evening_phone		TEXT,
	other_phone		TEXT,
	mailing_address		INT,
	billing_address		INT,
	home_ou			INT,
	dob			DATE		NOT NULL,
	active			BOOL		NOT NULL DEFAULT TRUE,
	master_account		BOOL		NOT NULL DEFAULT FALSE,
	super_user		BOOL		NOT NULL DEFAULT FALSE,
	usrgroup		SERIAL		NOT NULL,
	claims_returned_count	INT		NOT NULL DEFAULT 0,
	credit_forward_balance	NUMERIC(6,2)	NOT NULL DEFAULT 0.00,
	last_xact_id		TEXT		NOT NULL DEFAULT 'none',
	alert_message		TEXT,
	create_date		DATE		NOT NULL DEFAULT now()::DATE,
	expire_date		DATE		NOT NULL DEFAULT (now() + '3 years'::INTERVAL)::DATE
);
CREATE INDEX actor_usr_home_ou_idx ON actor.usr (home_ou);
CREATE INDEX actor_usr_mailing_address_idx ON actor.usr (mailing_address);
CREATE INDEX actor_usr_billing_address_idx ON actor.usr (billing_address);

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
INSERT INTO actor.usr ( profile, card, usrname, passwd, first_given_name, family_name, dob, master_account, super_user, ident_type, ident_value )
	VALUES ( 3, 1,'admin', 'open-ils', 'Administrator', '', '1979-01-22', TRUE, TRUE, 1, 'identification' );
INSERT INTO actor.usr ( profile, card, usrname, passwd, first_given_name, family_name, dob, master_account, super_user, ident_type, ident_value )
	VALUES ( 2, 2,'demo', 'demo', 'demo', 'user', '1979-01-22', FALSE, TRUE, 1, 'identification' );
INSERT INTO actor.usr ( profile, card, usrname, passwd, first_given_name, family_name, dob, master_account, super_user, ident_type, ident_value )
	VALUES ( 1, 3,'athens', 'athens', 'athens', 'user', '1979-01-22', FALSE, TRUE, 1, 'identification' );

CREATE TABLE actor.profile (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE
);
INSERT INTO actor.profile (name) VALUES ('ADULT');
INSERT INTO actor.profile (name) VALUES ('JUVENILE');
INSERT INTO actor.profile (name) VALUES ('STAFF');

CREATE TABLE actor.stat_cat (
	id		SERIAL  PRIMARY KEY,
	owner		INT     NOT NULL,
	name		TEXT    NOT NULL,
	opac_visible	BOOL NOT NULL DEFAULT FALSE,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE actor.stat_cat_entry (
	id		SERIAL  PRIMARY KEY,
	stat_cat	INT	NOT NULL,
	owner		INT     NOT NULL,
	value		TEXT    NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (owner,value)
);

CREATE TABLE actor.stat_cat_entry_usr_map (
	id		BIGSERIAL	PRIMARY KEY,
	stat_cat_entry	TEXT		NOT NULL,
	stat_cat	INT		NOT NULL,
	target_usr	INT		NOT NULL,
	CONSTRAINT sce_once_per_copy UNIQUE (target_usr,stat_cat)
);
CREATE INDEX actor_stat_cat_entry_usr_idx ON actor.stat_cat_entry_usr_map (target_usr);

CREATE TABLE actor.card (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id),
	barcode	TEXT	NOT NULL UNIQUE,
	active	BOOL	NOT NULL DEFAULT TRUE
);
CREATE INDEX actor_card_usr_idx ON actor.card (usr);

INSERT INTO actor.card (usr, barcode) VALUES (1,'101010101010101');
INSERT INTO actor.card (usr, barcode) VALUES (2,'101010101010102');
INSERT INTO actor.card (usr, barcode) VALUES (3,'101010101010103');


CREATE TABLE actor.org_unit_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	depth		INT	NOT NULL,
	parent		INT	REFERENCES actor.org_unit_type (id),
	can_have_vols	BOOL	NOT NULL DEFAULT TRUE,
	can_have_users	BOOL	NOT NULL DEFAULT TRUE
);
CREATE INDEX actor_org_unit_type_parent_idx ON actor.org_unit_type (parent);

-- The PINES levels
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users, can_have_vols) VALUES ( 'Consortium', 0, NULL, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users, can_have_vols) VALUES ( 'System', 1, 1, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, depth, parent) VALUES ( 'Branch', 2, 2 );
INSERT INTO actor.org_unit_type (name, depth, parent) VALUES ( 'Sub-lib', 3, 3 );
INSERT INTO actor.org_unit_type (name, depth, parent) VALUES ( 'Bookmobile', 3, 3 );

CREATE TABLE actor.org_unit (
	id		SERIAL	PRIMARY KEY,
	parent_ou	INT	REFERENCES actor.org_unit (id),
	ou_type		INT	NOT NULL REFERENCES actor.org_unit_type (id),
	ill_address	INT,
	holds_address	INT,
	mailing_address	INT,
	billing_address	INT,
	shortname	TEXT	NOT NULL,
	name		TEXT	NOT NULL
);
CREATE INDEX actor_org_unit_parent_ou_idx ON actor.org_unit (parent_ou);
CREATE INDEX actor_org_unit_ou_type_idx ON actor.org_unit (ou_type);
CREATE INDEX actor_org_unit_ill_address_idx ON actor.org_unit (ill_address);
CREATE INDEX actor_org_unit_billing_address_idx ON actor.org_unit (billing_address);
CREATE INDEX actor_org_unit_mailing_address_idx ON actor.org_unit (mailing_address);
CREATE INDEX actor_org_unit_holds_address_idx ON actor.org_unit (holds_address);

INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (NULL, 1, 'PINES', 'Georgia PINES Consortium');

CREATE TABLE actor.usr_access_entry (
	id		BIGSERIAL	PRIMARY KEY,
	usr		INT		NOT NULL REFERENCES actor.usr (id),
	org_unit	INT		NOT NULL REFERENCES actor.org_unit (id),
	CONSTRAINT usr_once_per_ou UNIQUE (usr,org_unit)
);


CREATE TABLE actor.perm_group (
	id	SERIAL	PRIMARY KEY,
	name	TEXT	NOT NULL,
	ou_type	INT	NOT NULL REFERENCES actor.org_unit_type (id)
);

CREATE TABLE actor.permission (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	code		TEXT	NOT NULL UNIQUE
);

CREATE TABLE actor.perm_group_permission_map (
	id		SERIAL	PRIMARY KEY,
	permission	INT	NOT NULL REFERENCES actor.permission (id),
	perm_group	INT	NOT NULL REFERENCES actor.perm_group (id),
	CONSTRAINT perm_once_per_group UNIQUE (permission, perm_group)
);

CREATE TABLE actor.perm_group_usr_map (
	id		BIGSERIAL	PRIMARY KEY,
	usr		INT		NOT NULL REFERENCES actor.usr (id),
	perm_group	INT		NOT NULL REFERENCES actor.perm_group (id),
	CONSTRAINT usr_once_per_group UNIQUE (usr, perm_group)
);

CREATE TABLE actor.usr_address (
	id		SERIAL	PRIMARY KEY,
	valid		BOOL	NOT NULL DEFAULT TRUE,
	address_type	TEXT	NOT NULL DEFAULT 'MAILING',
	usr		INT	NOT NULL REFERENCES actor.usr (id),
	street1		TEXT	NOT NULL,
	street2		TEXT,
	city		TEXT	NOT NULL,
	county		TEXT,
	state		TEXT	NOT NULL,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL
);

CREATE TABLE actor.org_address (
	id		SERIAL	PRIMARY KEY,
	valid		BOOL	NOT NULL DEFAULT TRUE,
	address_type	TEXT	NOT NULL DEFAULT 'MAILING',
	org_unit	INT	NOT NULL REFERENCES actor.org_unit (id),
	street1		TEXT	NOT NULL,
	street2		TEXT,
	city		TEXT	NOT NULL,
	county		TEXT,
	state		TEXT	NOT NULL,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL
);


COMMIT;

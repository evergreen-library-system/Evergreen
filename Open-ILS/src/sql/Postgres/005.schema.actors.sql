DROP SCHEMA actor CASCADE;

BEGIN;
CREATE SCHEMA actor;

CREATE TABLE actor.usr (
	id			SERIAL	PRIMARY KEY,
	usrid			TEXT	NOT NULL UNIQUE, -- barcode
	usrname			TEXT	NOT NULL UNIQUE,
	email			TEXT	CHECK (email ~ $re$^[[:alnum:]_\.]+@[[:alnum:]_]+(?:\.[[:alnum:]_])+$$re$),
	passwd			TEXT	NOT NULL,
	prefix			TEXT,
	first_given_name	TEXT	NOT NULL,
	second_given_name	TEXT,
	family_name		TEXT	NOT NULL,
	suffix			TEXT,
	address			INT,
	home_ou			INT,
	gender			CHAR(1) NOT NULL CHECK ( LOWER(gender) IN ('m','f') ),
	dob			DATE	NOT NULL,
	active			BOOL	NOT NULL DEFAULT TRUE,
	master_account		BOOL	NOT NULL DEFAULT FALSE,
	super_user		BOOL	NOT NULL DEFAULT FALSE,
	usrgoup			SERIAL	NOT NULL
);

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

INSERT INTO actor.usr ( usrid, usrname, passwd, first_given_name, family_name, gender, dob, master_account, super_user )
	VALUES ( 'admin', 'admin', 'open-ils', 'Administrator', '', 'm', '1979-01-22', TRUE, TRUE );

CREATE TABLE actor.org_unit_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	depth		INT	NOT NULL,
	parent		INT	REFERENCES actor.org_unit_type (id),
	can_have_users	BOOL	NOT NULL DEFAULT TRUE
);

INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users) VALUES ( 'Consortium', 0, NULL, FALSE );
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users) VALUES ( 'System', 1, 1, FALSE );
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users) VALUES ( 'Branch', 2, 2, TRUE );
INSERT INTO actor.org_unit_type (name, depth, parent, can_have_users) VALUES ( 'Sub-lib', 3, 3, TRUE );

CREATE TABLE actor.org_unit (
	id		SERIAL	PRIMARY KEY,
	parent_ou	INT	REFERENCES actor.org_unit (id),
	ou_type		INT	NOT NULL REFERENCES actor.org_unit_type (id),
	address		INT	NOT NULL,
	name1		TEXT	NOT NULL,
	name2		TEXT
);

CREATE TABLE actor.usr_access_entry (
	id		BIGSERIAL	PRIMARY KEY,
	usr		INT		REFERENCES actor.usr (id),
	org_unit	INT		REFERENCES actor.org_unit (id),
	CONSTRAINT usr_once_per_ou UNIQUE (usr,org_unit)
);


CREATE TABLE actor.perm_group (
	id	SERIAL	PRIMARY KEY,
	name	TEXT	NOT NULL,
	ou_type	INT	REFERENCES actor.org_unit_type (id)
);

CREATE TABLE actor.permission (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	code		TEXT	NOT NULL UNIQUE
);

CREATE TABLE actor.perm_group_permission_map (
	permission	INT	REFERENCES actor.permission (id) ON DELETE CASCADE,
	perm_group	INT	REFERENCES actor.perm_group (id) ON DELETE CASCADE,
	CONSTRAINT perm_once_per_group PRIMARY KEY (permission, perm_group)
);

CREATE TABLE actor.perm_group_usr_map (
	usr		INT	REFERENCES actor.usr (id) ON DELETE CASCADE,
	perm_group	INT	REFERENCES actor.perm_group (id) ON DELETE CASCADE,
	CONSTRAINT usr_once_per_group PRIMARY KEY (usr, perm_group)
);

CREATE TABLE actor.usr_address (
	id		SERIAL	PRIMARY KEY,
	valid		BOOL	NOT NULL DEFAULT TRUE,
	usr		INT	REFERENCES actor.usr (id) ON DELETE RESTRICT,
	street1		TEXT	NOT NULL,
	street2		TEXT,
	county		TEXT	NOT NULL,
	state		TEXT	NOT NULL,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL
);

ALTER TABLE actor.usr ADD CONSTRAINT usr_address_fkey FOREIGN KEY ( address ) REFERENCES actor.usr_address (id) ON DELETE RESTRICT;
ALTER TABLE actor.usr ADD CONSTRAINT usr_home_ou_fkey FOREIGN KEY ( home_ou ) REFERENCES actor.org_unit (id) ON DELETE RESTRICT;

COMMIT;

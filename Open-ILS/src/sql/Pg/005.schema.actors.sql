DROP SCHEMA actor CASCADE;

BEGIN;
CREATE SCHEMA actor;
COMMENT ON SCHEMA actor IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Schema: actor
 *
 * Holds all tables pertaining to users and libraries (org units).
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

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
	home_ou			INT		NOT NULL,
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
COMMENT ON TABLE actor.usr IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * User objects
 *
 * This table contains the core User objects that describe both
 * staff members and patrons.  The difference between the two
 * types of users is based on the user's permissions.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE INDEX actor_usr_home_ou_idx ON actor.usr (home_ou);
CREATE INDEX actor_usr_mailing_address_idx ON actor.usr (mailing_address);
CREATE INDEX actor_usr_billing_address_idx ON actor.usr (billing_address);

CREATE INDEX actor_usr_first_given_name_idx ON actor.usr (lower(first_given_name));
CREATE INDEX actor_usr_second_given_name_idx ON actor.usr (lower(second_given_name));
CREATE INDEX actor_usr_family_name_idx ON actor.usr (lower(family_name));

CREATE INDEX actor_usr_email_idx ON actor.usr (lower(email));

CREATE INDEX actor_usr_day_phone_idx ON actor.usr (lower(day_phone));
CREATE INDEX actor_usr_evening_phone_idx ON actor.usr (lower(evening_phone));
CREATE INDEX actor_usr_other_phone_idx ON actor.usr (lower(other_phone));

CREATE INDEX actor_usr_ident_value_idx ON actor.usr (lower(ident_value));
CREATE INDEX actor_usr_ident_value2_idx ON actor.usr (lower(ident_value2));

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
INSERT INTO actor.usr ( profile, card, usrname, passwd, first_given_name, family_name, dob, master_account, super_user, ident_type, ident_value, home_ou )
	VALUES ( 1, 1,'admin', 'open-ils', 'Administrator', 'System Account', '1979-01-22', TRUE, TRUE, 1, 'identification', 1 );


CREATE TABLE actor.usr_setting (
	id	BIGSERIAL	PRIMARY KEY,
	usr	INT		NOT NULL REFERENCES actor.usr ON DELETE CASCADE,
	name	TEXT		NOT NULL,
	value	TEXT		NOT NULL,
	CONSTRAINT usr_once_per_key UNIQUE (usr,name)
);
COMMENT ON TABLE actor.usr_setting IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * User settings
 *
 * This table contains any arbitrary settings that a client
 * program would like to save for a user.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE INDEX actor_usr_setting_usr_idx ON actor.usr_setting (usr);


CREATE TABLE actor.stat_cat (
	id		SERIAL  PRIMARY KEY,
	owner		INT     NOT NULL,
	name		TEXT    NOT NULL,
	opac_visible	BOOL NOT NULL DEFAULT FALSE,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);
COMMENT ON TABLE actor.stat_cat IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * User Statistical Catagories
 *
 * Local data collected about Users is placed into a Statistical
 * Catagory.  Here's where those catagories are defined.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


CREATE TABLE actor.stat_cat_entry (
	id		SERIAL  PRIMARY KEY,
	stat_cat	INT	NOT NULL,
	owner		INT     NOT NULL,
	value		TEXT    NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (owner,value)
);
COMMENT ON TABLE actor.stat_cat_entry IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * User Statistical Catagory Entries
 *
 * Local data collected about Users is placed into a Statistical
 * Catagory.  Each library can create entries into any of it's own
 * stat_cats, it's anscestors stat_cats, or it's descendants' stat_cats.
 *
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;


CREATE TABLE actor.stat_cat_entry_usr_map (
	id		BIGSERIAL	PRIMARY KEY,
	stat_cat_entry	TEXT		NOT NULL,
	stat_cat	INT		NOT NULL,
	target_usr	INT		NOT NULL,
	CONSTRAINT sc_once_per_usr UNIQUE (target_usr,stat_cat)
);
COMMENT ON TABLE actor.stat_cat_entry_usr_map IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Statistical Catagory Entry to User map
 *
 * Records the stat_cat entries for each user.
 *
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE INDEX actor_stat_cat_entry_usr_idx ON actor.stat_cat_entry_usr_map (target_usr);

CREATE TABLE actor.card (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id),
	barcode	TEXT	NOT NULL UNIQUE,
	active	BOOL	NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE actor.card IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Library Cards
 *
 * Each User has one or more library cards.  The current "main"
 * card is linked to here from the actor.usr table, and it is up
 * to the consortium policy whether more than one card can be
 * active for any one user at a given time.
 *
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE INDEX actor_card_usr_idx ON actor.card (usr);

INSERT INTO actor.card (usr, barcode) VALUES (1,'101010101010101');


CREATE TABLE actor.org_unit_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	opac_label	TEXT	NOT NULL,
	depth		INT	NOT NULL,
	parent		INT	REFERENCES actor.org_unit_type (id),
	can_have_vols	BOOL	NOT NULL DEFAULT TRUE,
	can_have_users	BOOL	NOT NULL DEFAULT TRUE
);
CREATE INDEX actor_org_unit_type_parent_idx ON actor.org_unit_type (parent);

-- The PINES levels
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent, can_have_users, can_have_vols) VALUES ( 'Consortium','Everywhere', 0, NULL, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent, can_have_users, can_have_vols) VALUES ( 'System','Local Library System', 1, 1, FALSE, FALSE );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent) VALUES ( 'Branch','This Branch', 2, 2 );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent) VALUES ( 'Sub-lib','This Specialized Library', 3, 3 );
INSERT INTO actor.org_unit_type (name, opac_label, depth, parent) VALUES ( 'Bookmobile','Your Bookmobile', 3, 3 );

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

INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (NULL, 1, 'CONS', 'Example Consortium');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (1, 2, 'SYS1', 'Example System 1');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (1, 2, 'SYS2', 'Example System 2');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (2, 3, 'BR1', 'Example Branch 1');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (2, 3, 'BR2', 'Example Branch 2');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (3, 3, 'BR3', 'Example Branch 3');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (3, 3, 'BR4', 'Example Branch 4');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (4, 4, 'SL1', 'Example Sub-lib 1');
INSERT INTO actor.org_unit (parent_ou, ou_type, shortname, name) VALUES (6, 5, 'BM1', 'Example Bookmobile 1');

CREATE TABLE actor.org_unit_setting (
	id		BIGSERIAL	PRIMARY KEY,
	org_unit	INT		NOT NULL REFERENCES actor.org_unit ON DELETE CASCADE,
	name		TEXT		NOT NULL,
	value		TEXT		NOT NULL,
	CONSTRAINT ou_once_per_key UNIQUE (org_unit,name)
);
COMMENT ON TABLE actor.org_unit_setting IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Org Unit settings
 *
 * This table contains any arbitrary settings that a client
 * program would like to save for an org unit.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE INDEX actor_org_unit_setting_usr_idx ON actor.org_unit_setting (org_unit);


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

CREATE INDEX actor_usr_addr_usr_idx ON actor.usr_address (usr);

CREATE INDEX actor_usr_addr_street1_idx ON actor.usr_address (lower(street1));
CREATE INDEX actor_usr_addr_street2_idx ON actor.usr_address (lower(street2));

CREATE INDEX actor_usr_addr_city_idx ON actor.usr_address (lower(city));
CREATE INDEX actor_usr_addr_state_idx ON actor.usr_address (lower(state));
CREATE INDEX actor_usr_addr_post_code_idx ON actor.usr_address (lower(post_code));


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

CREATE INDEX actor_org_address_org_unit_idx ON actor.org_address (org_unit);

INSERT INTO actor.org_address VALUES (DEFAULT,DEFAULT,DEFAULT,1,'123 Main St.',NULL,'Anywhere',NULL,'GA','US','30303');
UPDATE actor.org_unit SET holds_address = 1, ill_address = 1, billing_address = 1, mailing_address = 1;

COMMIT;

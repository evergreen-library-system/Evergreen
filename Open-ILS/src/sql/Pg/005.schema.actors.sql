DROP SCHEMA actor CASCADE;

BEGIN;
CREATE SCHEMA actor;
COMMENT ON SCHEMA actor IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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
	id			SERIAL				PRIMARY KEY,
	card			INT				UNIQUE, -- active card
	profile			INT				NOT NULL, -- patron profile
	usrname			TEXT				NOT NULL UNIQUE,
	email			TEXT,
	passwd			TEXT				NOT NULL,
	standing		INT				NOT NULL DEFAULT 1 REFERENCES config.standing (id) DEFERRABLE INITIALLY DEFERRED,
	ident_type		INT				NOT NULL REFERENCES config.identification_type (id) DEFERRABLE INITIALLY DEFERRED,
	ident_value		TEXT,
	ident_type2		INT				REFERENCES config.identification_type (id) DEFERRABLE INITIALLY DEFERRED,
	ident_value2		TEXT,
	net_access_level	INT				NOT NULL DEFAULT 1 REFERENCES config.net_access_level (id) DEFERRABLE INITIALLY DEFERRED,
	photo_url		TEXT,
	prefix			TEXT,
	first_given_name	TEXT				NOT NULL,
	second_given_name	TEXT,
	family_name		TEXT				NOT NULL,
	suffix			TEXT,
	alias			TEXT,
	day_phone		TEXT,
	evening_phone		TEXT,
	other_phone		TEXT,
	mailing_address		INT,
	billing_address		INT,
	home_ou			INT				NOT NULL,
	dob			TIMESTAMP WITH TIME ZONE,
	active			BOOL				NOT NULL DEFAULT TRUE,
	master_account		BOOL				NOT NULL DEFAULT FALSE,
	super_user		BOOL				NOT NULL DEFAULT FALSE,
	barred			BOOL				NOT NULL DEFAULT FALSE,
	deleted			BOOL				NOT NULL DEFAULT FALSE,
	usrgroup		SERIAL				NOT NULL,
	claims_returned_count	INT				NOT NULL DEFAULT 0,
	credit_forward_balance	NUMERIC(6,2)			NOT NULL DEFAULT 0.00,
	last_xact_id		TEXT				NOT NULL DEFAULT 'none',
	alert_message		TEXT,
	create_date		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	expire_date		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT (now() + '3 years'::INTERVAL)
);
COMMENT ON TABLE actor.usr IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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

CREATE RULE protect_user_delete AS ON DELETE TO actor.usr DO INSTEAD UPDATE actor.usr SET deleted = TRUE WHERE OLD.id = actor.usr.id;

CREATE TABLE actor.usr_note (
	id		BIGSERIAL			PRIMARY KEY,
	usr		BIGINT				NOT NULL REFERENCES actor.usr ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	creator		BIGINT				NOT NULL REFERENCES actor.usr ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	pub		BOOL				NOT NULL DEFAULT FALSE,
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);
CREATE INDEX actor_usr_note_usr_idx ON actor.usr_note (usr);

CREATE TABLE actor.usr_setting (
	id	BIGSERIAL	PRIMARY KEY,
	usr	INT		NOT NULL REFERENCES actor.usr ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	name	TEXT		NOT NULL,
	value	TEXT		NOT NULL,
	CONSTRAINT usr_once_per_key UNIQUE (usr,name)
);
COMMENT ON TABLE actor.usr_setting IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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
	CONSTRAINT sce_once_per_owner UNIQUE (stat_cat,owner,value)
);
COMMENT ON TABLE actor.stat_cat_entry IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * User Statistical Catagory Entries
 *
 * Local data collected about Users is placed into a Statistical
 * Catagory.  Each library can create entries into any of its own
 * stat_cats, its ancestors' stat_cats, or its descendants' stat_cats.
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
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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
	usr	INT	NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	barcode	TEXT	NOT NULL UNIQUE,
	active	BOOL	NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE actor.card IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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

CREATE TABLE actor.org_unit_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	opac_label	TEXT	NOT NULL,
	depth		INT	NOT NULL,
	parent		INT	REFERENCES actor.org_unit_type (id) DEFERRABLE INITIALLY DEFERRED,
	can_have_vols	BOOL	NOT NULL DEFAULT TRUE,
	can_have_users	BOOL	NOT NULL DEFAULT TRUE
);
CREATE INDEX actor_org_unit_type_parent_idx ON actor.org_unit_type (parent);

CREATE TABLE actor.org_unit (
	id		SERIAL	PRIMARY KEY,
	parent_ou	INT	REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	ou_type		INT	NOT NULL REFERENCES actor.org_unit_type (id) DEFERRABLE INITIALLY DEFERRED,
	ill_address	INT,
	holds_address	INT,
	mailing_address	INT,
	billing_address	INT,
	shortname	TEXT	NOT NULL,
	name		TEXT	NOT NULL,
	email		TEXT,
	phone		TEXT,
	opac_visible	BOOL	NOT NULL DEFAULT TRUE
);
CREATE INDEX actor_org_unit_parent_ou_idx ON actor.org_unit (parent_ou);
CREATE INDEX actor_org_unit_ou_type_idx ON actor.org_unit (ou_type);
CREATE INDEX actor_org_unit_ill_address_idx ON actor.org_unit (ill_address);
CREATE INDEX actor_org_unit_billing_address_idx ON actor.org_unit (billing_address);
CREATE INDEX actor_org_unit_mailing_address_idx ON actor.org_unit (mailing_address);
CREATE INDEX actor_org_unit_holds_address_idx ON actor.org_unit (holds_address);

CREATE TABLE actor.org_lasso (
    id      SERIAL  PRIMARY KEY,
    name   	TEXT    UNIQUE
);

CREATE TABLE actor.org_lasso_map (
    id          SERIAL  PRIMARY KEY,
    lasso       INT     NOT NULL REFERENCES actor.org_lasso (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org_unit    INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX ou_lasso_lasso_ou_idx ON actor.org_lasso_map (lasso, org_unit);
CREATE INDEX ou_lasso_org_unit_idx ON actor.org_lasso_map (org_unit);

CREATE TABLE actor.org_unit_proximity (
	id		BIGSERIAL	PRIMARY KEY,
	from_org	INT,
	to_org		INT,
	prox		INT
);
CREATE INDEX from_prox_idx ON actor.org_unit_proximity (from_org);

CREATE TABLE actor.hours_of_operation (
	id		INT	PRIMARY KEY REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	dow_0_open	TIME	NOT NULL DEFAULT '09:00',
	dow_0_close	TIME	NOT NULL DEFAULT '17:00',
	dow_1_open	TIME	NOT NULL DEFAULT '09:00',
	dow_1_close	TIME	NOT NULL DEFAULT '17:00',
	dow_2_open	TIME	NOT NULL DEFAULT '09:00',
	dow_2_close	TIME	NOT NULL DEFAULT '17:00',
	dow_3_open	TIME	NOT NULL DEFAULT '09:00',
	dow_3_close	TIME	NOT NULL DEFAULT '17:00',
	dow_4_open	TIME	NOT NULL DEFAULT '09:00',
	dow_4_close	TIME	NOT NULL DEFAULT '17:00',
	dow_5_open	TIME	NOT NULL DEFAULT '09:00',
	dow_5_close	TIME	NOT NULL DEFAULT '17:00',
	dow_6_open	TIME	NOT NULL DEFAULT '09:00',
	dow_6_close	TIME	NOT NULL DEFAULT '17:00'
);

CREATE TABLE actor.org_unit_closed (
	id		SERIAL				PRIMARY KEY,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	close_start	TIMESTAMP WITH TIME ZONE	NOT NULL,
	close_end	TIMESTAMP WITH TIME ZONE	NOT NULL,
	reason		TEXT
);

-- Workstation registration...
CREATE TABLE actor.workstation (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	owning_lib	INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE actor.usr_org_unit_opt_in (
	id		SERIAL				PRIMARY KEY,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	usr		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	staff		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	opt_in_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	opt_in_ws	INT				NOT NULL REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT usr_opt_in_once_per_org_unit UNIQUE (usr,org_unit)
);

CREATE TABLE actor.org_unit_setting (
	id		BIGSERIAL	PRIMARY KEY,
	org_unit	INT		NOT NULL REFERENCES actor.org_unit ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	name		TEXT		NOT NULL,
	value		TEXT		NOT NULL,
	CONSTRAINT ou_once_per_key UNIQUE (org_unit,name)
);
COMMENT ON TABLE actor.org_unit_setting IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
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
	id			SERIAL	PRIMARY KEY,
	valid			BOOL	NOT NULL DEFAULT TRUE,
	within_city_limits	BOOL	NOT NULL DEFAULT TRUE,
	address_type		TEXT	NOT NULL DEFAULT 'MAILING',
	usr			INT	NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	street1			TEXT	NOT NULL,
	street2			TEXT,
	city			TEXT	NOT NULL,
	county			TEXT,
	state			TEXT	NOT NULL,
	country			TEXT	NOT NULL,
	post_code		TEXT	NOT NULL
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
	org_unit	INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	street1		TEXT	NOT NULL,
	street2		TEXT,
	city		TEXT	NOT NULL,
	county		TEXT,
	state		TEXT	NOT NULL,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL
);

CREATE INDEX actor_org_address_org_unit_idx ON actor.org_address (org_unit);

CREATE OR REPLACE FUNCTION public.first5 ( TEXT ) RETURNS TEXT AS $$
	SELECT SUBSTRING( $1, 1, 5);
$$ LANGUAGE SQL;

CREATE TABLE actor.usr_standing_penalty (
	id			SERIAL	PRIMARY KEY,
	org_unit		INT	NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	usr			INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	standing_penalty	INT	NOT NULL REFERENCES config.standing_penalty (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	staff			INT	REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	set_date		TIMESTAMP WITH TIME ZONE	DEFAULT NOW()
);
COMMENT ON TABLE actor.usr_standing_penalty IS $$
/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * User standing penalties
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

CREATE INDEX actor_usr_standing_penalty_usr_idx ON actor.usr_standing_penalty (usr);


COMMIT;

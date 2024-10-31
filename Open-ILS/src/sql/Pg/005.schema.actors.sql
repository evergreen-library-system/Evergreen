/*
 * Copyright (C) 2005-2008  Equinox Software, Inc. / Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
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

DROP SCHEMA IF EXISTS actor CASCADE;

BEGIN;
CREATE SCHEMA actor;
COMMENT ON SCHEMA actor IS $$
Holds all tables pertaining to users and libraries (org units).
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
    guardian        TEXT,
    pref_prefix TEXT,
    pref_first_given_name TEXT,
    pref_second_given_name TEXT,
    pref_family_name TEXT,
    pref_suffix TEXT,
    name_keywords TEXT,
    name_kw_tsvector TSVECTOR,
	alias			TEXT,
	day_phone		TEXT,
	evening_phone		TEXT,
	other_phone		TEXT,
	mailing_address		INT,
	billing_address		INT,
	home_ou			INT				NOT NULL,
	dob			DATE,
	active			BOOL				NOT NULL DEFAULT TRUE,
	master_account		BOOL				NOT NULL DEFAULT FALSE,
	super_user		BOOL				NOT NULL DEFAULT FALSE,
	barred			BOOL				NOT NULL DEFAULT FALSE,
	deleted			BOOL				NOT NULL DEFAULT FALSE,
	juvenile		BOOL				NOT NULL DEFAULT FALSE,
	usrgroup		SERIAL				NOT NULL,
	claims_returned_count	INT				NOT NULL DEFAULT 0,
	credit_forward_balance	NUMERIC(6,2)			NOT NULL DEFAULT 0.00,
	last_xact_id		TEXT				NOT NULL DEFAULT 'none',
	create_date		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT now(),
	expire_date		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT (now() + '3 years'::INTERVAL),
	claims_never_checked_out_count  INT         NOT NULL DEFAULT 0,
    last_update_time    TIMESTAMP WITH TIME ZONE,
    locale                  TEXT REFERENCES config.i18n_locale(code) INITIALLY DEFERRED
);
COMMENT ON TABLE actor.usr IS $$
User objects

This table contains the core User objects that describe both
staff members and patrons.  The difference between the two
types of users is based on the user's permissions.
$$;

CREATE INDEX actor_usr_home_ou_idx ON actor.usr (home_ou);
CREATE INDEX actor_usr_usrgroup_idx ON actor.usr (usrgroup);
CREATE INDEX actor_usr_mailing_address_idx ON actor.usr (mailing_address);
CREATE INDEX actor_usr_billing_address_idx ON actor.usr (billing_address);

CREATE INDEX actor_usr_first_given_name_idx ON actor.usr (evergreen.lowercase(first_given_name));
CREATE INDEX actor_usr_second_given_name_idx ON actor.usr (evergreen.lowercase(second_given_name));
CREATE INDEX actor_usr_family_name_idx ON actor.usr (evergreen.lowercase(family_name));
CREATE INDEX actor_usr_first_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(first_given_name));
CREATE INDEX actor_usr_second_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(second_given_name));
CREATE INDEX actor_usr_family_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(family_name));
CREATE INDEX actor_usr_usrname_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(usrname));
CREATE INDEX actor_usr_guardian_idx ON actor.usr (evergreen.lowercase(guardian));
CREATE INDEX actor_usr_guardian_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(guardian));

CREATE INDEX actor_usr_pref_first_given_name_idx ON actor.usr (evergreen.lowercase(pref_first_given_name));
CREATE INDEX actor_usr_pref_second_given_name_idx ON actor.usr (evergreen.lowercase(pref_second_given_name));
CREATE INDEX actor_usr_pref_family_name_idx ON actor.usr (evergreen.lowercase(pref_family_name));
CREATE INDEX actor_usr_pref_first_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(pref_first_given_name));
CREATE INDEX actor_usr_pref_second_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(pref_second_given_name));
CREATE INDEX actor_usr_pref_family_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(pref_family_name));

CREATE INDEX actor_usr_usrname_idx ON actor.usr (evergreen.lowercase(usrname));
CREATE INDEX actor_usr_email_idx ON actor.usr (evergreen.lowercase(email));

CREATE INDEX actor_usr_day_phone_idx ON actor.usr (evergreen.lowercase(day_phone));
CREATE INDEX actor_usr_evening_phone_idx ON actor.usr (evergreen.lowercase(evening_phone));
CREATE INDEX actor_usr_other_phone_idx ON actor.usr (evergreen.lowercase(other_phone));

CREATE INDEX actor_usr_day_phone_idx_numeric ON actor.usr USING BTREE
    (evergreen.lowercase(REGEXP_REPLACE(day_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_evening_phone_idx_numeric ON actor.usr USING BTREE
    (evergreen.lowercase(REGEXP_REPLACE(evening_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_other_phone_idx_numeric ON actor.usr USING BTREE
    (evergreen.lowercase(REGEXP_REPLACE(other_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_ident_value_idx ON actor.usr (evergreen.lowercase(ident_value));
CREATE INDEX actor_usr_ident_value2_idx ON actor.usr (evergreen.lowercase(ident_value2));

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

CREATE OR REPLACE FUNCTION actor.au_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_update_time := now();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER au_update_trig
	BEFORE INSERT OR UPDATE ON actor.usr
	FOR EACH ROW EXECUTE PROCEDURE actor.au_updated();

CREATE TRIGGER actor_crypt_pw_update_trigger
	BEFORE UPDATE ON actor.usr FOR EACH ROW
	EXECUTE PROCEDURE actor.crypt_pw_update ();

CREATE TRIGGER actor_crypt_pw_insert_trigger
	BEFORE INSERT ON actor.usr FOR EACH ROW
	EXECUTE PROCEDURE actor.crypt_pw_insert ();

CREATE RULE protect_user_delete AS ON DELETE TO actor.usr DO INSTEAD UPDATE actor.usr SET deleted = TRUE WHERE OLD.id = actor.usr.id;

CREATE OR REPLACE FUNCTION actor.user_ingest_name_keywords() 
    RETURNS TRIGGER AS $func$
BEGIN
    NEW.name_kw_tsvector := TO_TSVECTOR(
        COALESCE(NEW.prefix, '')                || ' ' || 
        COALESCE(NEW.first_given_name, '')      || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.first_given_name), '') || ' ' || 
        COALESCE(NEW.second_given_name, '')     || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.second_given_name), '') || ' ' || 
        COALESCE(NEW.family_name, '')           || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.family_name), '') || ' ' || 
        COALESCE(NEW.suffix, '')                || ' ' || 
        COALESCE(NEW.pref_prefix, '')            || ' ' || 
        COALESCE(NEW.pref_first_given_name, '')  || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_first_given_name), '') || ' ' || 
        COALESCE(NEW.pref_second_given_name, '') || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_second_given_name), '') || ' ' || 
        COALESCE(NEW.pref_family_name, '')       || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_family_name), '') || ' ' || 
        COALESCE(NEW.pref_suffix, '')            || ' ' || 
        COALESCE(NEW.name_keywords, '')
    );
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

-- Add after the batch upate above to avoid duplicate updates.
CREATE TRIGGER user_ingest_name_keywords_tgr 
    BEFORE INSERT OR UPDATE ON actor.usr 
    FOR EACH ROW EXECUTE PROCEDURE actor.user_ingest_name_keywords();

CREATE TABLE actor.usr_setting (
	id	BIGSERIAL	PRIMARY KEY,
	usr	INT		NOT NULL REFERENCES actor.usr ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	name	TEXT		NOT NULL REFERENCES config.usr_setting_type (name) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
	value	TEXT		NOT NULL,
	CONSTRAINT usr_once_per_key UNIQUE (usr,name)
);
COMMENT ON TABLE actor.usr_setting IS $$
User settings

This table contains any arbitrary settings that a client
program would like to save for a user.
$$;

CREATE INDEX actor_usr_setting_usr_idx ON actor.usr_setting (usr);

-- special indexes for phone number searches
CREATE INDEX actor_usr_setting_phone_values_idx
    ON actor.usr_setting (evergreen.lowercase(value))
    WHERE name IN ('opac.default_phone', 'opac.default_sms_notify');

CREATE INDEX actor_usr_setting_phone_values_numeric_idx
    ON actor.usr_setting (evergreen.lowercase(REGEXP_REPLACE(value, '[^0-9]', '', 'g')))
    WHERE name IN ('opac.default_phone', 'opac.default_sms_notify');

CREATE TABLE actor.stat_cat_sip_fields (
    field   CHAR(2) PRIMARY KEY,
    name    TEXT    NOT NULL,
    one_only  BOOL    NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE actor.stat_cat_sip_fields IS $$
Actor Statistical Category SIP Fields

Contains the list of valid SIP Field identifiers for
Statistical Categories.
$$;

CREATE TABLE actor.stat_cat (
	id		SERIAL  PRIMARY KEY,
	owner		INT     NOT NULL,
	name		TEXT    NOT NULL,
	opac_visible	BOOL NOT NULL DEFAULT FALSE,
	usr_summary     BOOL NOT NULL DEFAULT FALSE,
    sip_field   CHAR(2) REFERENCES actor.stat_cat_sip_fields(field) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    sip_format  TEXT,
    checkout_archive    BOOL NOT NULL DEFAULT FALSE,
	required	BOOL NOT NULL DEFAULT FALSE,
	allow_freetext	BOOL NOT NULL DEFAULT TRUE,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);
COMMENT ON TABLE actor.stat_cat IS $$
User Statistical Catagories

Local data collected about Users is placed into a Statistical
Catagory.  Here's where those catagories are defined.
$$;


CREATE TABLE actor.stat_cat_entry (
	id		SERIAL  PRIMARY KEY,
	stat_cat	INT	NOT NULL,
	owner		INT     NOT NULL,
	value		TEXT    NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (stat_cat,owner,value)
);
COMMENT ON TABLE actor.stat_cat_entry IS $$
User Statistical Catagory Entries

Local data collected about Users is placed into a Statistical
Catagory.  Each library can create entries into any of its own
stat_cats, its ancestors' stat_cats, or its descendants' stat_cats.
$$;


CREATE TABLE actor.stat_cat_entry_usr_map (
	id		BIGSERIAL	PRIMARY KEY,
	stat_cat_entry	TEXT		NOT NULL,
	stat_cat	INT		NOT NULL,
	target_usr	INT		NOT NULL,
	CONSTRAINT sc_once_per_usr UNIQUE (target_usr,stat_cat)
);
COMMENT ON TABLE actor.stat_cat_entry_usr_map IS $$
Statistical Catagory Entry to User map

Records the stat_cat entries for each user.
$$;

CREATE INDEX actor_stat_cat_entry_usr_idx ON actor.stat_cat_entry_usr_map (target_usr);

CREATE FUNCTION actor.stat_cat_check() RETURNS trigger AS $func$
DECLARE
    sipfield actor.stat_cat_sip_fields%ROWTYPE;
    use_count INT;
BEGIN
    IF NEW.sip_field IS NOT NULL THEN
        SELECT INTO sipfield * FROM actor.stat_cat_sip_fields WHERE field = NEW.sip_field;
        IF sipfield.one_only THEN
            SELECT INTO use_count count(id) FROM actor.stat_cat WHERE sip_field = NEW.sip_field AND id != NEW.id;
            IF use_count > 0 THEN
                RAISE EXCEPTION 'Sip field cannot be used twice';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER actor_stat_cat_sip_update_trigger
    BEFORE INSERT OR UPDATE ON actor.stat_cat FOR EACH ROW
    EXECUTE PROCEDURE actor.stat_cat_check();

CREATE TABLE actor.card (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	barcode	TEXT	NOT NULL UNIQUE,
	active	BOOL	NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE actor.card IS $$
Library Cards

Each User has one or more library cards.  The current "main"
card is linked to here from the actor.usr table, and it is up
to the consortium policy whether more than one card can be
active for any one user at a given time.
$$;

CREATE INDEX actor_card_usr_idx ON actor.card (usr);
CREATE INDEX actor_card_barcode_evergreen_lowercase_idx ON actor.card (evergreen.lowercase(barcode));

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
	shortname	TEXT	NOT NULL UNIQUE,
	name		TEXT	NOT NULL UNIQUE,
	email		TEXT,
	phone		TEXT,
	opac_visible	BOOL	NOT NULL DEFAULT TRUE,
	fiscal_calendar INT     NOT NULL DEFAULT 1   -- foreign key constraint to be added later
);
CREATE INDEX actor_org_unit_parent_ou_idx ON actor.org_unit (parent_ou);
CREATE INDEX actor_org_unit_ou_type_idx ON actor.org_unit (ou_type);
CREATE INDEX actor_org_unit_ill_address_idx ON actor.org_unit (ill_address);
CREATE INDEX actor_org_unit_billing_address_idx ON actor.org_unit (billing_address);
CREATE INDEX actor_org_unit_mailing_address_idx ON actor.org_unit (mailing_address);
CREATE INDEX actor_org_unit_holds_address_idx ON actor.org_unit (holds_address);

CREATE OR REPLACE FUNCTION actor.org_unit_parent_protect () RETURNS TRIGGER AS $$
	DECLARE
		current_aou actor.org_unit%ROWTYPE;
		seen_ous    INT[];
		depth_count INT;
	BEGIN
		current_aou := NEW;
		depth_count := 0;
		seen_ous := ARRAY[NEW.id];

		IF (TG_OP = 'UPDATE') THEN
			IF (NEW.parent_ou IS NOT DISTINCT FROM OLD.parent_ou) THEN
				RETURN NEW; -- Doing an UPDATE with no change, just return it
			END IF;
		END IF;

		LOOP
			IF current_aou.parent_ou IS NULL THEN -- Top of the org tree?
				RETURN NEW; -- No loop. Carry on.
			END IF;
			IF current_aou.parent_ou = ANY(seen_ous) THEN -- Parent is one we have seen?
				RAISE 'OU LOOP: Saw % twice', current_aou.parent_ou; -- LOOP! ABORT!
			END IF;
			-- Get the next one!
			SELECT INTO current_aou * FROM actor.org_unit WHERE id = current_aou.parent_ou;
			seen_ous := seen_ous || current_aou.id;
			depth_count := depth_count + 1;
			IF depth_count = 100 THEN
				RAISE 'OU CHECK TOO DEEP';
			END IF;
		END LOOP;

		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER actor_org_unit_parent_protect_trigger
    BEFORE INSERT OR UPDATE ON actor.org_unit FOR EACH ROW
    EXECUTE PROCEDURE actor.org_unit_parent_protect ();

CREATE TABLE actor.org_lasso (
    id      SERIAL  PRIMARY KEY,
    name   	TEXT    UNIQUE,
    global  BOOL    NOT NULL DEFAULT FALSE
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

CREATE TABLE actor.stat_cat_entry_default (
	id		SERIAL	PRIMARY KEY,
        stat_cat_entry	INT	NOT NULL REFERENCES actor.stat_cat_entry(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	stat_cat	INT	NOT NULL REFERENCES actor.stat_cat(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	owner		INT	NOT NULL REFERENCES actor.org_unit(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT sced_once_per_owner UNIQUE (stat_cat,owner)
);
COMMENT ON TABLE actor.stat_cat_entry_default IS $$
User Statistical Category Default Entry

A library may choose one of the stat_cat entries to be the
default entry.
$$;


CREATE TABLE actor.org_unit_proximity_adjustment (
    id                  SERIAL   PRIMARY KEY,
    item_circ_lib       INT         REFERENCES actor.org_unit (id),
    item_owning_lib     INT         REFERENCES actor.org_unit (id),
    copy_location       INT,        -- REFERENCES asset.copy_location (id),
    hold_pickup_lib     INT         REFERENCES actor.org_unit (id),
    hold_request_lib    INT         REFERENCES actor.org_unit (id),
    pos                 INT         NOT NULL DEFAULT 0,
    absolute_adjustment BOOL        NOT NULL DEFAULT FALSE,
    prox_adjustment     NUMERIC,
    circ_mod            TEXT,       -- REFERENCES config.circ_modifier (code),
    CONSTRAINT prox_adj_criterium CHECK (COALESCE(item_circ_lib::TEXT,item_owning_lib::TEXT,copy_location::TEXT,hold_pickup_lib::TEXT,hold_request_lib::TEXT,circ_mod) IS NOT NULL)
);
CREATE UNIQUE INDEX prox_adj_once_idx ON actor.org_unit_proximity_adjustment (
    COALESCE(item_circ_lib, -1),
    COALESCE(item_owning_lib, -1),
    COALESCE(copy_location, -1),
    COALESCE(hold_pickup_lib, -1),
    COALESCE(hold_request_lib, -1),
    COALESCE(circ_mod, ''),
    pos
);
CREATE INDEX prox_adj_circ_lib_idx ON actor.org_unit_proximity_adjustment (item_circ_lib);
CREATE INDEX prox_adj_owning_lib_idx ON actor.org_unit_proximity_adjustment (item_owning_lib);
CREATE INDEX prox_adj_copy_location_idx ON actor.org_unit_proximity_adjustment (copy_location);
CREATE INDEX prox_adj_pickup_lib_idx ON actor.org_unit_proximity_adjustment (hold_pickup_lib);
CREATE INDEX prox_adj_request_lib_idx ON actor.org_unit_proximity_adjustment (hold_request_lib);
CREATE INDEX prox_adj_circ_mod_idx ON actor.org_unit_proximity_adjustment (circ_mod);

CREATE TABLE actor.hours_of_operation (
	id		INT	PRIMARY KEY REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	dow_0_open	TIME	NOT NULL DEFAULT '09:00',
	dow_0_close	TIME	NOT NULL DEFAULT '17:00',
    dow_0_note  TEXT,
	dow_1_open	TIME	NOT NULL DEFAULT '09:00',
	dow_1_close	TIME	NOT NULL DEFAULT '17:00',
    dow_1_note  TEXT,
	dow_2_open	TIME	NOT NULL DEFAULT '09:00',
	dow_2_close	TIME	NOT NULL DEFAULT '17:00',
    dow_2_note  TEXT,
	dow_3_open	TIME	NOT NULL DEFAULT '09:00',
	dow_3_close	TIME	NOT NULL DEFAULT '17:00',
    dow_3_note  TEXT,
	dow_4_open	TIME	NOT NULL DEFAULT '09:00',
	dow_4_close	TIME	NOT NULL DEFAULT '17:00',
    dow_4_note  TEXT,
	dow_5_open	TIME	NOT NULL DEFAULT '09:00',
	dow_5_close	TIME	NOT NULL DEFAULT '17:00',
    dow_5_note  TEXT,
	dow_6_open	TIME	NOT NULL DEFAULT '09:00',
	dow_6_close	TIME	NOT NULL DEFAULT '17:00',
    dow_6_note  TEXT
);
COMMENT ON TABLE actor.hours_of_operation IS $$
When does this org_unit usually open and close?  (Variations
are expressed in the actor.org_unit_closed table.)
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_0_open IS $$
When does this org_unit open on Monday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_0_close IS $$
When does this org_unit close on Monday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_1_open IS $$
When does this org_unit open on Tuesday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_1_close IS $$
When does this org_unit close on Tuesday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_2_open IS $$
When does this org_unit open on Wednesday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_2_close IS $$
When does this org_unit close on Wednesday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_3_open IS $$
When does this org_unit open on Thursday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_3_close IS $$
When does this org_unit close on Thursday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_4_open IS $$
When does this org_unit open on Friday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_4_close IS $$
When does this org_unit close on Friday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_5_open IS $$
When does this org_unit open on Saturday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_5_close IS $$
When does this org_unit close on Saturday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_6_open IS $$
When does this org_unit open on Sunday?
$$;
COMMENT ON COLUMN actor.hours_of_operation.dow_6_close IS $$
When does this org_unit close on Sunday?
$$;

CREATE TABLE actor.org_unit_closed (
	id		SERIAL				PRIMARY KEY,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	close_start	TIMESTAMP WITH TIME ZONE	NOT NULL,
	close_end	TIMESTAMP WITH TIME ZONE	NOT NULL,
    full_day    BOOLEAN                     NOT NULL DEFAULT FALSE,
    multi_day   BOOLEAN                     NOT NULL DEFAULT FALSE,
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
CREATE INDEX usr_org_unit_opt_in_staff_idx ON actor.usr_org_unit_opt_in ( staff );

CREATE TABLE actor.org_unit_setting (
	id		BIGSERIAL	PRIMARY KEY,
	org_unit	INT		NOT NULL REFERENCES actor.org_unit ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	name		TEXT	NOT NULL REFERENCES config.org_unit_setting_type DEFERRABLE INITIALLY DEFERRED,
	value		TEXT		NOT NULL,
	CONSTRAINT ou_once_per_key UNIQUE (org_unit,name),
	CONSTRAINT aous_must_be_json CHECK ( evergreen.is_json(value) )
);
COMMENT ON TABLE actor.org_unit_setting IS $$
Org Unit settings

This table contains any arbitrary settings that a client
program would like to save for an org unit.
$$;

CREATE INDEX actor_org_unit_setting_usr_idx ON actor.org_unit_setting (org_unit);

-- Log each change in oust to oustl, so admins can see what they messed up if someting stops working.
CREATE OR REPLACE FUNCTION ous_change_log() RETURNS TRIGGER AS $ous_change_log$
    DECLARE
    original TEXT;
    BEGIN
        -- Check for which setting is being updated, and log it.
        SELECT INTO original value FROM actor.org_unit_setting WHERE name = NEW.name AND org_unit = NEW.org_unit;
                
        INSERT INTO config.org_unit_setting_type_log (org,original_value,new_value,field_name) VALUES (NEW.org_unit, original, NEW.value, NEW.name);
        
        RETURN NEW;
    END;
$ous_change_log$ LANGUAGE plpgsql;    

CREATE TRIGGER log_ous_change
    BEFORE INSERT OR UPDATE ON actor.org_unit_setting
    FOR EACH ROW EXECUTE PROCEDURE ous_change_log();

CREATE OR REPLACE FUNCTION ous_delete_log() RETURNS TRIGGER AS $ous_delete_log$
    DECLARE
    original TEXT;
    BEGIN
        -- Check for which setting is being updated, and log it.
        SELECT INTO original value FROM actor.org_unit_setting WHERE name = OLD.name AND org_unit = OLD.org_unit;
                
        INSERT INTO config.org_unit_setting_type_log (org,original_value,new_value,field_name) VALUES (OLD.org_unit, original, 'null', OLD.name);
        
        RETURN OLD;
    END;
$ous_delete_log$ LANGUAGE plpgsql;    

CREATE TRIGGER log_ous_del
    BEFORE DELETE ON actor.org_unit_setting
    FOR EACH ROW EXECUTE PROCEDURE ous_delete_log();




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
	state			TEXT,
	country			TEXT	NOT NULL,
	post_code		TEXT	NOT NULL,
    pending         BOOL    NOT NULL DEFAULT FALSE,
	replaces	    INT	REFERENCES actor.usr_address (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX actor_usr_addr_usr_idx ON actor.usr_address (usr);

CREATE INDEX actor_usr_addr_street1_idx ON actor.usr_address (evergreen.lowercase(street1));
CREATE INDEX actor_usr_addr_street2_idx ON actor.usr_address (evergreen.lowercase(street2));

CREATE INDEX actor_usr_addr_city_idx ON actor.usr_address (evergreen.lowercase(city));
CREATE INDEX actor_usr_addr_state_idx ON actor.usr_address (evergreen.lowercase(state));
CREATE INDEX actor_usr_addr_post_code_idx ON actor.usr_address (evergreen.lowercase(post_code));

CREATE TABLE actor.usr_password_reset (
  id SERIAL PRIMARY KEY,
  uuid TEXT NOT NULL, 
  usr BIGINT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED, 
  request_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(), 
  has_been_reset BOOL NOT NULL DEFAULT false
);
COMMENT ON TABLE actor.usr_password_reset IS $$
Self-serve password reset requests
$$;
CREATE UNIQUE INDEX actor_usr_password_reset_uuid_idx ON actor.usr_password_reset (uuid);
CREATE INDEX actor_usr_password_reset_usr_idx ON actor.usr_password_reset (usr);
CREATE INDEX actor_usr_password_reset_request_time_idx ON actor.usr_password_reset (request_time);
CREATE INDEX actor_usr_password_reset_has_been_reset_idx ON actor.usr_password_reset (has_been_reset);

CREATE TABLE actor.org_address (
	id		SERIAL	PRIMARY KEY,
	valid		BOOL	NOT NULL DEFAULT TRUE,
	address_type	TEXT	NOT NULL DEFAULT 'MAILING',
	org_unit	INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	street1		TEXT	NOT NULL,
	street2		TEXT,
	city		TEXT	NOT NULL,
	county		TEXT,
	state		TEXT,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL,
	san			TEXT,
	latitude	FLOAT,
	longitude	FLOAT
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
	set_date		TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	stop_date		TIMESTAMP WITH TIME ZONE
);
COMMENT ON TABLE actor.usr_standing_penalty IS $$
User standing penalties
$$;

CREATE INDEX actor_usr_standing_penalty_usr_idx ON actor.usr_standing_penalty (usr);
CREATE INDEX actor_usr_standing_penalty_staff_idx ON actor.usr_standing_penalty ( staff );


CREATE TABLE actor.usr_saved_search (
    id              SERIAL          PRIMARY KEY,
	owner           INT             NOT NULL REFERENCES actor.usr (id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	name            TEXT            NOT NULL,
	create_date     TIMESTAMPTZ     NOT NULL DEFAULT now(),
	query_text      TEXT            NOT NULL,
	query_type      TEXT            NOT NULL
	                                CONSTRAINT valid_query_text CHECK (
	                                query_type IN ( 'URL' )) DEFAULT 'URL',
	                                -- we may add other types someday
	target          TEXT            NOT NULL
	                                CONSTRAINT valid_target CHECK (
	                                target IN ( 'record', 'metarecord', 'callnumber' )),
	CONSTRAINT name_once_per_user UNIQUE (owner, name)
);

CREATE TABLE actor.address_alert (
    id              SERIAL  PRIMARY KEY,
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    active          BOOL    NOT NULL DEFAULT TRUE,
    match_all       BOOL    NOT NULL DEFAULT TRUE,
    alert_message   TEXT    NOT NULL,
    street1         TEXT,
    street2         TEXT,
    city            TEXT,
    county          TEXT,
    state           TEXT,
    country         TEXT,
    post_code       TEXT,
    mailing_address BOOL    NOT NULL DEFAULT FALSE,
    billing_address BOOL    NOT NULL DEFAULT FALSE
);

CREATE TABLE actor.usr_activity (
    id          BIGSERIAL   PRIMARY KEY,
    usr         INT         REFERENCES actor.usr (id) ON DELETE SET NULL,
    etype       INT         NOT NULL REFERENCES config.usr_activity_type (id),
    event_time  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_data  TEXT
);
CREATE INDEX usr_activity_usr_idx ON actor.usr_activity (usr);

CREATE TABLE actor.toolbar (
    id          BIGSERIAL   PRIMARY KEY,
    ws          INT         REFERENCES actor.workstation (id) ON DELETE CASCADE,
    org         INT         REFERENCES actor.org_unit (id) ON DELETE CASCADE,
    usr         INT         REFERENCES actor.usr (id) ON DELETE CASCADE,
    label       TEXT        NOT NULL,
    layout      TEXT        NOT NULL,
    CONSTRAINT only_one_type CHECK (
        (ws IS NOT NULL AND COALESCE(org,usr) IS NULL) OR
        (org IS NOT NULL AND COALESCE(ws,usr) IS NULL) OR
        (usr IS NOT NULL AND COALESCE(org,ws) IS NULL)
    ),
    CONSTRAINT layout_must_be_json CHECK ( is_json(layout) )
);
CREATE UNIQUE INDEX label_once_per_ws ON actor.toolbar (ws, label) WHERE ws IS NOT NULL;
CREATE UNIQUE INDEX label_once_per_org ON actor.toolbar (org, label) WHERE org IS NOT NULL;
CREATE UNIQUE INDEX label_once_per_usr ON actor.toolbar (usr, label) WHERE usr IS NOT NULL;

CREATE TYPE actor.org_unit_custom_tree_purpose AS ENUM ('opac');
CREATE TABLE actor.org_unit_custom_tree (
    id              SERIAL  PRIMARY KEY,
    active          BOOLEAN DEFAULT FALSE,
    purpose         actor.org_unit_custom_tree_purpose NOT NULL DEFAULT 'opac' UNIQUE
);

CREATE TABLE actor.org_unit_custom_tree_node (
    id              SERIAL  PRIMARY KEY,
    tree            INTEGER REFERENCES actor.org_unit_custom_tree (id) DEFERRABLE INITIALLY DEFERRED,
    org_unit        INTEGER NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    parent_node     INTEGER REFERENCES actor.org_unit_custom_tree_node (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    sibling_order   INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT aouctn_once_per_org UNIQUE (tree, org_unit)
);

CREATE TABLE actor.search_query (
    id          SERIAL PRIMARY KEY, 
    label       TEXT NOT NULL, -- i18n
    query_text  TEXT NOT NULL -- QP text
);

CREATE TABLE actor.search_filter_group (
    id          SERIAL      PRIMARY KEY,
    owner       INT         NOT NULL REFERENCES actor.org_unit (id) 
                            ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    code        TEXT        NOT NULL, -- for CGI, etc.
    label       TEXT        NOT NULL, -- i18n
    create_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT  asfg_label_once_per_org UNIQUE (owner, label),
    CONSTRAINT  asfg_code_once_per_org UNIQUE (owner, code)
);

CREATE TABLE actor.search_filter_group_entry (
    id          SERIAL  PRIMARY KEY,
    grp         INT     NOT NULL REFERENCES actor.search_filter_group(id) 
                        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    pos         INT     NOT NULL DEFAULT 0,
    query       INT     NOT NULL REFERENCES actor.search_query(id) 
                        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT asfge_query_once_per_group UNIQUE (grp, query)
);

CREATE TABLE actor.usr_message (
	id		SERIAL				PRIMARY KEY,
	usr		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	title		TEXT,					   
	message		TEXT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	deleted		BOOL				NOT NULL DEFAULT FALSE,
	read_date	TIMESTAMP WITH TIME ZONE,
	sending_lib	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	pub		BOOL				NOT NULL DEFAULT FALSE,
	stop_date		TIMESTAMP WITH TIME ZONE,
	editor	BIGINT REFERENCES actor.usr (id),
	edit_date		TIMESTAMP WITH TIME ZONE
);
CREATE INDEX aum_usr ON actor.usr_message (usr);
CREATE INDEX aum_editor ON actor.usr_message (editor);
ALTER TABLE actor.usr_standing_penalty ALTER COLUMN id SET DEFAULT nextval('actor.usr_message_id_seq'::regclass);
ALTER TABLE actor.usr_standing_penalty ADD COLUMN usr_message BIGINT REFERENCES actor.usr_message(id);
CREATE INDEX usr_standing_penalty_usr_message_idx ON actor.usr_standing_penalty (usr_message);

CREATE RULE protect_usr_message_delete AS
	ON DELETE TO actor.usr_message DO INSTEAD (
		UPDATE	actor.usr_message
		  SET	deleted = TRUE
		  WHERE	OLD.id = actor.usr_message.id
	);

-- limited view to ensure that a library user who somehow
-- manages to figure out how to access pcrud cannot change
-- the text of messages sent them
CREATE VIEW actor.usr_message_limited
AS SELECT * FROM actor.usr_message WHERE pub AND NOT deleted;

CREATE FUNCTION actor.restrict_usr_message_limited () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        UPDATE actor.usr_message
        SET    read_date = NEW.read_date,
               deleted   = NEW.deleted
        WHERE  id = NEW.id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER restrict_usr_message_limited_tgr
    INSTEAD OF UPDATE OR INSERT OR DELETE ON actor.usr_message_limited
    FOR EACH ROW EXECUTE PROCEDURE actor.restrict_usr_message_limited();

-- combined view of actor.usr_standing_penalty and actor.usr_message for populating
-- staff Notes (formerly Messages) interface

CREATE VIEW actor.usr_message_penalty AS
SELECT -- ausp with or without messages
    ausp.id AS "id",
    ausp.id AS "ausp_id",
    aum.id AS "aum_id",
    ausp.org_unit AS "org_unit",
    ausp.org_unit AS "ausp_org_unit",
    aum.sending_lib AS "aum_sending_lib",
    ausp.usr AS "usr",
    ausp.usr as "ausp_usr",
    aum.usr as "aum_usr",
    ausp.standing_penalty AS "standing_penalty",
    ausp.staff AS "staff",
    ausp.set_date AS "create_date",
    ausp.set_date AS "ausp_set_date",
    aum.create_date AS "aum_create_date",
    ausp.stop_date AS "stop_date",
    ausp.stop_date AS "ausp_stop_date",
    aum.stop_date AS "aum_stop_date",
    ausp.usr_message AS "ausp_usr_message",
    aum.title AS "title",
    aum.message AS "message",
    aum.deleted AS "deleted",
    aum.read_date AS "read_date",
    aum.pub AS "pub",
    aum.editor AS "editor",
    aum.edit_date AS "edit_date"
FROM
    actor.usr_standing_penalty ausp
    LEFT JOIN actor.usr_message aum ON (ausp.usr_message = aum.id)
        UNION ALL
SELECT -- aum without penalties
    aum.id AS "id",
    NULL::INT AS "ausp_id",
    aum.id AS "aum_id",
    aum.sending_lib AS "org_unit",
    NULL::INT AS "ausp_org_unit",
    aum.sending_lib AS "aum_sending_lib",
    aum.usr AS "usr",
    NULL::INT as "ausp_usr",
    aum.usr as "aum_usr",
    NULL::INT AS "standing_penalty",
    NULL::INT AS "staff",
    aum.create_date AS "create_date",
    NULL::TIMESTAMPTZ AS "ausp_set_date",
    aum.create_date AS "aum_create_date",
    aum.stop_date AS "stop_date",
    NULL::TIMESTAMPTZ AS "ausp_stop_date",
    aum.stop_date AS "aum_stop_date",
    NULL::INT AS "ausp_usr_message",
    aum.title AS "title",
    aum.message AS "message",
    aum.deleted AS "deleted",
    aum.read_date AS "read_date",
    aum.pub AS "pub",
    aum.editor AS "editor",
    aum.edit_date AS "edit_date"
FROM
    actor.usr_message aum
    LEFT JOIN actor.usr_standing_penalty ausp ON (ausp.usr_message = aum.id)
WHERE NOT aum.deleted AND ausp.id IS NULL
;

CREATE TABLE actor.passwd_type (
    code        TEXT PRIMARY KEY,
    name        TEXT UNIQUE NOT NULL,
    login       BOOLEAN NOT NULL DEFAULT FALSE,
    regex       TEXT,   -- pending
    crypt_algo  TEXT,   -- e.g. 'bf'

    -- gen_salt() iter count used with each new salt.
    -- A non-NULL value for iter_count is our indication the 
    -- password is salted and encrypted via crypt()
    iter_count  INTEGER CHECK (iter_count IS NULL OR iter_count > 0)
);

CREATE TABLE actor.passwd (
    id          SERIAL PRIMARY KEY,
    usr         INTEGER NOT NULL REFERENCES actor.usr(id)
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    salt        TEXT, -- will be NULL for non-crypt'ed passwords
    passwd      TEXT NOT NULL,
    passwd_type TEXT NOT NULL REFERENCES actor.passwd_type(code)
                DEFERRABLE INITIALLY DEFERRED,
    create_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    edit_date   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT  passwd_type_once_per_user UNIQUE (usr, passwd_type)
);

CREATE OR REPLACE FUNCTION actor.create_salt(pw_type TEXT)
    RETURNS TEXT AS $$
DECLARE
    type_row actor.passwd_type%ROWTYPE;
BEGIN
    /* Returns a new salt based on the passwd_type encryption settings.
     * Returns NULL If the password type is not crypt()'ed.
     */

    SELECT INTO type_row * FROM actor.passwd_type WHERE code = pw_type;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No such password type: %', pw_type;
    END IF;

    IF type_row.iter_count IS NULL THEN
        -- This password type is unsalted.  That's OK.
        RETURN NULL;
    END IF;

    RETURN gen_salt(type_row.crypt_algo, type_row.iter_count);
END;
$$ LANGUAGE PLPGSQL;


/* 
    TODO: when a user changes their password in the application, the
    app layer has access to the bare password.  At that point, we have
    the opportunity to store the new password without the MD5(MD5())
    intermediate hashing.  Do we care?  We would need a way to indicate
    which passwords have the legacy intermediate hashing and which don't
    so the app layer would know whether it should perform the intermediate
    hashing.  In either event, with the exception of migrate_passwd(), the
    DB functions know or care nothing about intermediate hashing.  Every
    password is just a value that may or may not be internally crypt'ed. 
*/

CREATE OR REPLACE FUNCTION actor.set_passwd(
    pw_usr INTEGER, pw_type TEXT, new_pass TEXT, new_salt TEXT DEFAULT NULL)
    RETURNS BOOLEAN AS $$
DECLARE
    pw_salt TEXT;
    pw_text TEXT;
BEGIN
    /* Sets the password value, creating a new actor.passwd row if needed.
     * If the password type supports it, the new_pass value is crypt()'ed.
     * For crypt'ed passwords, the salt comes from one of 3 places in order:
     * new_salt (if present), existing salt (if present), newly created 
     * salt.
     */

    IF new_salt IS NOT NULL THEN
        pw_salt := new_salt;
    ELSE 
        pw_salt := actor.get_salt(pw_usr, pw_type);

        IF pw_salt IS NULL THEN
            /* We have no salt for this user + type.  Assume they want a 
             * new salt.  If this type is unsalted, create_salt() will 
             * return NULL. */
            pw_salt := actor.create_salt(pw_type);
        END IF;
    END IF;

    IF pw_salt IS NULL THEN 
        pw_text := new_pass; -- unsalted, use as-is.
    ELSE
        pw_text := CRYPT(new_pass, pw_salt);
    END IF;

    UPDATE actor.passwd 
        SET passwd = pw_text, salt = pw_salt, edit_date = NOW()
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF NOT FOUND THEN
        -- no password row exists for this user + type.  Create one.
        INSERT INTO actor.passwd (usr, passwd_type, salt, passwd) 
            VALUES (pw_usr, pw_type, pw_salt, pw_text);
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION actor.get_salt(pw_usr INTEGER, pw_type TEXT)
    RETURNS TEXT AS $$
DECLARE
    pw_salt TEXT;
    type_row actor.passwd_type%ROWTYPE;
BEGIN
    /* Returns the salt for the requested user + type.  If the password 
     * type of "main" is requested and no password exists in actor.passwd, 
     * the user's existing password is migrated and the new salt is returned.
     * Returns NULL if the password type is not crypt'ed (iter_count is NULL).
     */

    SELECT INTO pw_salt salt FROM actor.passwd 
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF FOUND THEN
        RETURN pw_salt;
    END IF;

    IF pw_type = 'main' THEN
        -- Main password has not yet been migrated. 
        -- Do it now and return the newly created salt.
        RETURN actor.migrate_passwd(pw_usr);
    END IF;

    -- We have no salt to return.  actor.create_salt() needed.
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION 
    actor.migrate_passwd(pw_usr INTEGER) RETURNS TEXT AS $$
DECLARE
    pw_salt TEXT;
    usr_row actor.usr%ROWTYPE;
BEGIN
    /* Migrates legacy actor.usr.passwd value to actor.passwd with 
     * a password type 'main' and returns the new salt.  For backwards
     * compatibility with existing CHAP-style API's, we perform a 
     * layer of intermediate MD5(MD5()) hashing.  This is intermediate
     * hashing is not required of other passwords.
     */

    -- Avoid calling get_salt() here, because it may result in a 
    -- migrate_passwd() call, creating a loop.
    SELECT INTO pw_salt salt FROM actor.passwd 
        WHERE usr = pw_usr AND passwd_type = 'main';

    -- Only migrate passwords that have not already been migrated.
    IF FOUND THEN
        RETURN pw_salt;
    END IF;

    SELECT INTO usr_row * FROM actor.usr WHERE id = pw_usr;

    pw_salt := actor.create_salt('main');

    PERFORM actor.set_passwd(
        pw_usr, 'main', MD5(pw_salt || usr_row.passwd), pw_salt);

    -- clear the existing password
    UPDATE actor.usr SET passwd = '' WHERE id = usr_row.id;

    RETURN pw_salt;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION 
    actor.verify_passwd(pw_usr INTEGER, pw_type TEXT, test_passwd TEXT) 
    RETURNS BOOLEAN AS $$
DECLARE
    pw_salt TEXT;
BEGIN
    /* Returns TRUE if the password provided matches the in-db password.  
     * If the password type is salted, we compare the output of CRYPT().
     * NOTE: test_passwd is MD5(salt || MD5(password)) for legacy 
     * 'main' passwords.
     */

    SELECT INTO pw_salt salt FROM actor.passwd 
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF NOT FOUND THEN
        -- no such password
        RETURN FALSE;
    END IF;

    IF pw_salt IS NULL THEN
        -- Password is unsalted, compare the un-CRYPT'ed values.
        RETURN EXISTS (
            SELECT TRUE FROM actor.passwd WHERE 
                usr = pw_usr AND
                passwd_type = pw_type AND
                passwd = test_passwd
        );
    END IF;

    RETURN EXISTS (
        SELECT TRUE FROM actor.passwd WHERE 
            usr = pw_usr AND
            passwd_type = pw_type AND
            passwd = CRYPT(test_passwd, pw_salt)
    );
END;
$$ STRICT LANGUAGE PLPGSQL;

-- Remove all activity entries by activity type, 
-- except the most recent entry per user. 
CREATE OR REPLACE FUNCTION
    actor.purge_usr_activity_by_type(act_type INTEGER)
    RETURNS VOID AS $$
DECLARE
    cur_usr INTEGER;
BEGIN
    FOR cur_usr IN SELECT DISTINCT(usr)
        FROM actor.usr_activity WHERE etype = act_type LOOP
        DELETE FROM actor.usr_activity WHERE id IN (
            SELECT id
            FROM actor.usr_activity
            WHERE usr = cur_usr AND etype = act_type
            ORDER BY event_time DESC OFFSET 1
        );

    END LOOP;
END $$ LANGUAGE PLPGSQL;

CREATE TABLE actor.workstation_setting (
    id          SERIAL PRIMARY KEY,
    workstation INT    NOT NULL REFERENCES actor.workstation (id) 
                       ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT   NOT NULL REFERENCES config.workstation_setting_type (name) 
                       ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    value       JSON   NOT NULL,
    CONSTRAINT  ws_once_per_key UNIQUE (workstation, name)
);

CREATE INDEX actor_workstation_setting_workstation_idx 
    ON actor.workstation_setting (workstation);

CREATE TYPE actor.cascade_setting_summary AS (
    name TEXT,
    value JSON,
    has_org_setting BOOLEAN,
    has_user_setting BOOLEAN,
    has_workstation_setting BOOLEAN
);

CREATE OR REPLACE FUNCTION actor.get_cascade_setting(
    setting_name TEXT, org_id INT, user_id INT, workstation_id INT) 
    RETURNS actor.cascade_setting_summary AS
$FUNC$
DECLARE
    setting_value JSON;
    summary actor.cascade_setting_summary;
    org_setting_type config.org_unit_setting_type%ROWTYPE;
BEGIN

    summary.name := setting_name;

    -- Collect the org setting type status first in case we exit early.
    -- The existance of an org setting type is not considered
    -- privileged information.
    SELECT INTO org_setting_type * 
        FROM config.org_unit_setting_type WHERE name = setting_name;
    IF FOUND THEN
        summary.has_org_setting := TRUE;
    ELSE
        summary.has_org_setting := FALSE;
    END IF;

    -- User and workstation settings have the same priority.
    -- Start with user settings since that's the simplest code path.
    -- The workstation_id is ignored if no user_id is provided.
    IF user_id IS NOT NULL THEN

        SELECT INTO summary.value value FROM actor.usr_setting
            WHERE usr = user_id AND name = setting_name;

        IF FOUND THEN
            -- if we have a value, we have a setting type
            summary.has_user_setting := TRUE;

            IF workstation_id IS NOT NULL THEN
                -- Only inform the caller about the workstation
                -- setting type disposition when a workstation id is
                -- provided.  Otherwise, it's NULL to indicate UNKNOWN.
                summary.has_workstation_setting := FALSE;
            END IF;

            RETURN summary;
        END IF;

        -- no user setting value, but a setting type may exist
        SELECT INTO summary.has_user_setting EXISTS (
            SELECT TRUE FROM config.usr_setting_type 
            WHERE name = setting_name
        );

        IF workstation_id IS NOT NULL THEN 

            IF NOT summary.has_user_setting THEN
                -- A workstation setting type may only exist when a user
                -- setting type does not.

                SELECT INTO summary.value value 
                    FROM actor.workstation_setting         
                    WHERE workstation = workstation_id AND name = setting_name;

                IF FOUND THEN
                    -- if we have a value, we have a setting type
                    summary.has_workstation_setting := TRUE;
                    RETURN summary;
                END IF;

                -- no value, but a setting type may exist
                SELECT INTO summary.has_workstation_setting EXISTS (
                    SELECT TRUE FROM config.workstation_setting_type 
                    WHERE name = setting_name
                );
            END IF;

            -- Finally make use of the workstation to determine the org
            -- unit if none is provided.
            IF org_id IS NULL AND summary.has_org_setting THEN
                SELECT INTO org_id owning_lib 
                    FROM actor.workstation WHERE id = workstation_id;
            END IF;
        END IF;
    END IF;

    -- Some org unit settings are protected by a view permission.
    -- First see if we have any data that needs protecting, then 
    -- check the permission if needed.

    IF NOT summary.has_org_setting THEN
        RETURN summary;
    END IF;

    -- avoid putting the value into the summary until we confirm
    -- the value should be visible to the caller.
    SELECT INTO setting_value value 
        FROM actor.org_unit_ancestor_setting(setting_name, org_id);

    IF NOT FOUND THEN
        -- No value found -- perm check is irrelevant.
        RETURN summary;
    END IF;

    IF org_setting_type.view_perm IS NOT NULL THEN

        IF user_id IS NULL THEN
            RAISE NOTICE 'Perm check required but no user_id provided';
            RETURN summary;
        END IF;

        IF NOT permission.usr_has_perm(
            user_id, (SELECT code FROM permission.perm_list 
                WHERE id = org_setting_type.view_perm), org_id) 
        THEN
            RAISE NOTICE 'Perm check failed for user % on %',
                user_id, org_setting_type.view_perm;
            RETURN summary;
        END IF;
    END IF;

    -- Perm check succeeded or was not necessary.
    summary.value := setting_value;
    RETURN summary;
END;
$FUNC$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION actor.get_cascade_setting_batch(
    setting_names TEXT[], org_id INT, user_id INT, workstation_id INT) 
    RETURNS SETOF actor.cascade_setting_summary AS
$FUNC$
-- Returns a row per setting matching the setting name order.  If no 
-- value is applied, NULL is returned to retain name-response ordering.
DECLARE
    setting_name TEXT;
    summary actor.cascade_setting_summary;
BEGIN
    FOREACH setting_name IN ARRAY setting_names LOOP
        SELECT INTO summary * FROM actor.get_cascade_setting(
            setting_Name, org_id, user_id, workstation_id);
        RETURN NEXT summary;
    END LOOP;
END;
$FUNC$ LANGUAGE PLPGSQL;

CREATE TABLE actor.usr_privacy_waiver (
    id BIGSERIAL PRIMARY KEY,
    usr BIGINT NOT NULL REFERENCES actor.usr(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name TEXT NOT NULL,
    place_holds BOOL DEFAULT FALSE,
    pickup_holds BOOL DEFAULT FALSE,
    view_history BOOL DEFAULT FALSE,
    checkout_items BOOL DEFAULT FALSE
);
CREATE INDEX actor_usr_privacy_waiver_usr_idx ON actor.usr_privacy_waiver (usr);

CREATE TABLE IF NOT EXISTS actor.usr_mfa_exception (
    id      SERIAL  PRIMARY KEY,
    usr     BIGINT  NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    ingress TEXT    -- disregard MFA requirement for specific ehow (ingress types, like 'sip2'), or NULL for all
);

CREATE TABLE actor.usr_mfa_factor_map (
    id          SERIAL  PRIMARY KEY,
    usr         BIGINT  NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    factor      TEXT    NOT NULL REFERENCES config.mfa_factor (name) DEFERRABLE INITIALLY DEFERRED,
    purpose     TEXT    NOT NULL DEFAULT 'mfa', -- mfa || login, for now
    add_time    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX factor_purpose_usr_once ON actor.usr_mfa_factor_map (usr, purpose, factor);

----- OTP URI destroyer: Removes the TOTP password entry if the user knows the secret NOW -----
CREATE OR REPLACE FUNCTION actor.remove_otpauth_uri(
    usr_id INT,
    otype TEXT,
    purpose TEXT,
    proof TEXT,
    fuzziness INT DEFAULT 1
) RETURNS BOOL AS $f$

use Pass::OTP;
use Pass::OTP::URI;

my $usr_id = shift;
my $otype = shift;
my $purpose = shift;
my $proof = shift;
my $fuzziness_width = shift // 1;

if ($otype eq 'webauthn') { # nothing to prove
    my $waq = spi_prepare('DELETE FROM actor.passwd WHERE usr = $1 AND passwd_type = $2 || $$-$$ || $3;', 'INTEGER', 'TEXT', 'TEXT');
    my $res = spi_exec_prepared($waq, $usr_id, $otype, $purpose);
    spi_freeplan($waq);
    return 1;
}

# Normalize the proof value
$proof =~ s/\D//g;
return 0 unless $proof; # all-0s is not valid

my $q = spi_prepare('SELECT actor.otpauth_uri($1, $2, $3) AS uri;', 'INTEGER', 'TEXT', 'TEXT');
my $otp_uri = spi_exec_prepared($q, {limit => 1}, $usr_id, $otype, $purpose)->{rows}[0]{uri};
spi_freeplan($q);

return 0 unless $otp_uri;

my %otp_config = Pass::OTP::URI::parse($otp_uri);

for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
    $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
    my $otp_code = Pass::OTP::otp(%otp_config);
    if ($otp_code eq $proof) {
        $q = spi_prepare('DELETE FROM actor.passwd WHERE usr = $1 AND passwd_type = $2 || $$-$$ || $3;', 'INTEGER', 'TEXT', 'TEXT');
        my $res = spi_exec_prepared($q, $usr_id, $otype, $purpose);
        spi_freeplan($q);
        return 1;
    }
}

return 0;
$f$ LANGUAGE PLPERLU;

----- OTP proof generator: find the TOTP code, optionally with fuzziness -----
CREATE OR REPLACE FUNCTION actor.otpauth_uri_get_proof(
    otp_uri TEXT,
    fuzziness INT DEFAULT 0
) RETURNS TABLE ( period_step INT, proof TEXT) AS $f$

use Pass::OTP;
use Pass::OTP::URI;

my $otp_uri = shift;
my $fuzziness_width = shift // 0;

return undef unless $otp_uri;

my %otp_config = Pass::OTP::URI::parse($otp_uri);
return undef unless $otp_config{type};

for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
    $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
    return_next({period_step => $fuzziness, proof => Pass::OTP::otp(%otp_config)});
}

return undef;

$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION actor.otpauth_uri_get_proof(
    usr_id INT,
    otype TEXT,
    purpose TEXT,
    fuzziness INT DEFAULT 0
) RETURNS TABLE ( period_step INT, proof TEXT) AS $f$
BEGIN
    RETURN QUERY
      SELECT * FROM actor.otpauth_uri_get_proof( actor.otpauth_uri($1, $2, $3), $4 );
    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

----- TOTP URI generator: Saves the secret on the first call for each user ID -----
CREATE OR REPLACE FUNCTION actor.otpauth_uri(
    usr_id INT,
    otype TEXT DEFAULT 'totp',
    purpose TEXT DEFAULT 'mfa',
    additional_params HSTORE DEFAULT ''::HSTORE -- this can be used to pass a start-time parameter to offset totp calc
) RETURNS TEXT AS $f$
DECLARE
    issuer      TEXT := 'Evergreen';
    algorithm   TEXT := 'SHA1';
    digits      TEXT := '6';
    period      TEXT := '30';
    counter     TEXT := '0';
    otp_secret  TEXT;
    otp_params  HSTORE;
    uri         TEXT;
    param_name  TEXT;
    uri_otype  TEXT;
BEGIN

    IF additional_params IS NULL THEN additional_params = ''::HSTORE; END IF;

    -- we're going to be a bit strict here, for now
    IF otype NOT IN ('webauthn','email','sms','totp','hotp') THEN RETURN NULL; END IF;
    IF purpose NOT IN ('mfa','login') THEN RETURN NULL; END IF;

    uri_otype := otype;
    IF otype NOT IN ('totp','hotp') THEN
        uri_otype := 'totp'; -- others are time-based, but with different settings
    END IF;

    -- protect "our" keys
    additional_params := additional_params - ARRAY['issuer','algorithm','digits','period'];

    SELECT passwd, salt::HSTORE INTO otp_secret, otp_params FROM actor.passwd WHERE usr = usr_id AND passwd_type = otype || '-' || purpose;

    IF NOT FOUND THEN

        issuer := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.issuer' AND enabled),
            issuer
        );

        algorithm := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.algorithm' AND enabled),
            algorithm
        );

        digits := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.digits' AND enabled),
            digits
        );

        period := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.period' AND enabled),
            period
        );

        otp_params := HSTORE('counter', counter)
                      || HSTORE('issuer', issuer)
                      || HSTORE('algorithm', UPPER(algorithm))
                      || HSTORE('digits', digits)
                      || HSTORE('period', period);

        IF additional_params ? 'counter' THEN
            otp_params := otp_params - 'counter';
        END IF;

        otp_params := additional_params || otp_params;

        WITH new_secret AS (
            INSERT INTO actor.passwd (usr, salt, passwd, passwd_type)
                VALUES (usr_id, otp_params::TEXT, gen_random_uuid()::TEXT, otype || '-' || purpose)
                RETURNING passwd, salt
        ) SELECT passwd, salt::HSTORE INTO otp_secret, otp_params FROM new_secret;

    ELSE
        otp_params := otp_params - akeys(additional_params); -- remove what we're receiving
        otp_params := additional_params || otp_params;
        IF additional_params != ''::HSTORE THEN -- new additional params were passed, let's save the salt again
            UPDATE actor.passwd SET salt = otp_params::TEXT WHERE usr = usr_id AND passwd_type = otype || '-' || purpose;
        END IF;
    END IF;


    uri :=  'otpauth://' || uri_otype || '/' || evergreen.uri_escape(otp_params -> 'issuer') || ':' || usr_id::TEXT
            ||'?secret='    || evergreen.encode_base32(otp_secret);

    FOREACH param_name IN ARRAY akeys(otp_params) LOOP
        uri := uri || '&' || evergreen.uri_escape(param_name) || '=' || evergreen.uri_escape(otp_params -> param_name);
    END LOOP;

    RETURN uri;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TABLE actor.patron_loader_log (
    id SERIAL,
    session BIGINT,
    org_unit INTEGER NOT NULL,
    event TEXT,
    record_count INTEGER,
    logtime TIMESTAMP DEFAULT NOW()
);
ALTER TABLE actor.patron_loader_log ADD CONSTRAINT actor_patron_loader_log_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.patron_loader_header_map ADD CONSTRAINT config_patron_loader_header_map_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.patron_loader_value_map ADD CONSTRAINT config_patron_loader_value_map_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;

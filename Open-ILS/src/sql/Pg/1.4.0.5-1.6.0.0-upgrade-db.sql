/*
 * Copyright (C) 2009  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
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
 *
 */



DROP SCHEMA acq CASCADE;
DROP SCHEMA serial CASCADE;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('1.6.0.0');
 
CREATE TABLE config.standing_penalty (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	label		TEXT	NOT NULL,
	block_list	TEXT
);
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (1,'PATRON_EXCEEDS_FINES','Patron exceeds fine threshold','CIRC|HOLD|RENEW');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (2,'PATRON_EXCEEDS_OVERDUE_COUNT','Patron exceeds max overdue item threshold','CIRC|HOLD|RENEW');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (3,'PATRON_EXCEEDS_CHECKOUT_COUNT','Patron exceeds max checked out item threshold','CIRC');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (4,'PATRON_EXCEEDS_COLLECTIONS_WARNING','Patron exceeds pre-collections warning fine threshold','CIRC|HOLD|RENEW');

INSERT INTO config.standing_penalty (id,name,label) VALUES (20,'ALERT_NOTE','Alerting Note, no blocks');
INSERT INTO config.standing_penalty (id,name,label) VALUES (21,'SILENT_NOTE','Note, no blocks');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (22,'STAFF_C','Alerting block on Circ','CIRC');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (23,'STAFF_CH','Alerting block on Circ and Hold','CIRC|HOLD');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (24,'STAFF_CR','Alerting block on Circ and Renew','CIRC|RENEW');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (25,'STAFF_CHR','Alerting block on Circ, Hold and Renew','CIRC|HOLD|RENEW');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (26,'STAFF_HR','Alerting block on Hold and Renew','HOLD|RENEW');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (27,'STAFF_H','Alerting block on Hold','HOLD');
INSERT INTO config.standing_penalty (id,name,label,block_list) VALUES (28,'STAFF_R','Alerting block on Renew','RENEW');

SELECT SETVAL('config.standing_penalty_id_seq', 100);

CREATE TABLE config.billing_type (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL,
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    default_price   NUMERIC(6,2),
    CONSTRAINT billing_type_once_per_lib UNIQUE (name, owner)
);

INSERT INTO config.billing_type (id, name, owner) VALUES ( 1, 'Overdue Materials', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 2, 'Long Overdue Collection Fee', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 3, 'Lost Materials', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 4, 'Lost Materials Processing Fee', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 5, 'System: Deposit', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 6, 'System: Rental', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 7, 'Damaged Item', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 8, 'Damaged Item Processing Fee', 1);
INSERT INTO config.billing_type (id, name, owner) VALUES ( 9, 'Notification Fee', 1);

SELECT SETVAL('config.billing_type_id_seq'::TEXT, 100);
 
ALTER TABLE actor.usr ADD COLUMN alias TEXT;
ALTER TABLE actor.usr ADD COLUMN juvenile BOOL;
ALTER TABLE auditor.actor_usr_history ADD COLUMN alias TEXT;
ALTER TABLE auditor.actor_usr_history ADD COLUMN juvenile BOOL;

ALTER TABLE actor.usr ALTER COLUMN juvenile SET DEFAULT FALSE;
UPDATE actor.usr SET juvenile=FALSE;


DROP TABLE actor.usr_standing_penalty;
CREATE TABLE actor.usr_standing_penalty (
	id			SERIAL	PRIMARY KEY,
	org_unit		INT	NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	usr			INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	standing_penalty	INT	NOT NULL REFERENCES config.standing_penalty (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	staff			INT	REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	set_date		TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	stop_date		TIMESTAMP WITH TIME ZONE,
	note			TEXT
);
CREATE INDEX actor_usr_standing_penalty_usr_idx ON actor.usr_standing_penalty (usr);


ALTER TABLE actor.usr_address ADD COLUMN pending BOOL;
ALTER TABLE actor.usr_address ADD COLUMN replaces INT;
ALTER TABLE auditor.actor_usr_address_history ADD COLUMN pending BOOL;
ALTER TABLE auditor.actor_usr_address_history ADD COLUMN replaces INT;

ALTER TABLE actor.usr_address ALTER COLUMN pending SET DEFAULT FALSE;
UPDATE actor.usr_address SET pending = FALSE;


CREATE TABLE permission.grp_penalty_threshold (
    id          SERIAL          PRIMARY KEY,
    grp         INT             NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org_unit    INT             NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    penalty     INT             NOT NULL REFERENCES config.standing_penalty (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    threshold   NUMERIC(8,2)    NOT NULL,
    CONSTRAINT penalty_grp_once UNIQUE (grp,penalty)
);

INSERT INTO permission.grp_penalty_threshold (grp,org_unit,penalty,threshold) VALUES (1,1,1,10.0);
INSERT INTO permission.grp_penalty_threshold (grp,org_unit,penalty,threshold) VALUES (1,1,2,10.0);
INSERT INTO permission.grp_penalty_threshold (grp,org_unit,penalty,threshold) VALUES (1,1,3,10.0);
SELECT SETVAL('permission.grp_penalty_threshold_id_seq'::TEXT, (SELECT MAX(id) FROM permission.grp_penalty_threshold));



CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_nd(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
--
-- Return a set of all the org units for which a given user has a given
-- permission, granted directly (not through inheritance from a parent
-- org unit).
--
-- The permissions apply to a minimum depth of the org unit hierarchy,
-- for the org unit(s) to which the user is assigned.  (They also apply
-- to the subordinates of those org units, but we don't report the
-- subordinates here.)
--
-- For purposes of this function, the permission.usr_work_ou_map table
-- defines which users belong to which org units.  I.e. we ignore the
-- home_ou column of actor.usr.
--
-- The result set may contain duplicates, which should be eliminated
-- by a DISTINCT clause.
--
DECLARE
	b_super       BOOLEAN;
	n_perm        INTEGER;
	n_min_depth   INTEGER; 
	n_work_ou     INTEGER;
	n_curr_ou     INTEGER;
	n_depth       INTEGER;
	n_curr_depth  INTEGER;
BEGIN
	--
	-- Check for superuser
	--
	SELECT INTO b_super
		super_user
	FROM
		actor.usr
	WHERE
		id = user_id;
	--
	IF NOT FOUND THEN
		return;				-- No user?  No permissions.
	ELSIF b_super THEN
		--
		-- Super user has all permissions everywhere
		--
		FOR n_work_ou IN
			SELECT
				id
			FROM
				actor.org_unit
			WHERE
				parent_ou IS NULL
		LOOP
			RETURN NEXT n_work_ou; 
		END LOOP;
		RETURN;
	END IF;
	--
	-- Translate the permission name
	-- to a numeric permission id
	--
	SELECT INTO n_perm
		id
	FROM
		permission.perm_list
	WHERE
		code = perm_code;
	--
	IF NOT FOUND THEN
		RETURN;               -- No such permission
	END IF;
	--
	-- Find the highest-level org unit (i.e. the minimum depth)
	-- to which the permission is applied for this user
	--
	-- This query is modified from the one in permission.usr_perms().
	--
	SELECT INTO n_min_depth
		min( depth )
	FROM	(
		SELECT depth 
		  FROM permission.usr_perm_map upm
		 WHERE upm.usr = user_id 
		   AND upm.perm = n_perm
       				UNION
		SELECT	gpm.depth
		  FROM	permission.grp_perm_map gpm
		  WHERE	gpm.perm = n_perm 
	        AND gpm.grp IN (
	 		   SELECT	(permission.grp_ancestors(
					(SELECT profile FROM actor.usr WHERE id = user_id)
				)).id
			)
       				UNION
		SELECT	p.depth
		  FROM	permission.grp_perm_map p 
		  WHERE p.perm = n_perm
		    AND p.grp IN (
		  		SELECT (permission.grp_ancestors(m.grp)).id 
				FROM   permission.usr_grp_map m
				WHERE  m.usr = user_id
			)
	) AS x;
	--
	IF NOT FOUND THEN
		RETURN;                -- No such permission for this user
	END IF;
	--
	-- Identify the org units to which the user is assigned.  Note that
	-- we pay no attention to the home_ou column in actor.usr.
	--
	FOR n_work_ou IN
		SELECT
			work_ou
		FROM
			permission.usr_work_ou_map
		WHERE
			usr = user_id
	LOOP            -- For each org unit to which the user is assigned
		--
		-- Determine the level of the org unit by a lookup in actor.org_unit_type.
		-- We take it on faith that this depth agrees with the actual hierarchy
		-- defined in actor.org_unit.
		--
		SELECT INTO n_depth
		    type.depth
		FROM
		    actor.org_unit_type type
		        INNER JOIN actor.org_unit ou
		            ON ( ou.ou_type = type.id )
		WHERE
		    ou.id = n_work_ou;
		--
		IF NOT FOUND THEN
			CONTINUE;        -- Maybe raise exception?
		END IF;
		--
		-- Compare the depth of the work org unit to the
		-- minimum depth, and branch accordingly
		--
		IF n_depth = n_min_depth THEN
			--
			-- The org unit is at the right depth, so return it.
			--
			RETURN NEXT n_work_ou;
		ELSIF n_depth > n_min_depth THEN
			--
			-- Traverse the org unit tree toward the root,
			-- until you reach the minimum depth determined above
			--
			n_curr_depth := n_depth;
			n_curr_ou := n_work_ou;
			WHILE n_curr_depth > n_min_depth LOOP
				SELECT INTO n_curr_ou
					parent_ou
				FROM
					actor.org_unit
				WHERE
					id = n_curr_ou;
				--
				IF FOUND THEN
					n_curr_depth := n_curr_depth - 1;
				ELSE
					--
					-- This can happen only if the hierarchy defined in
					-- actor.org_unit is corrupted, or out of sync with
					-- the depths defined in actor.org_unit_type.
					-- Maybe we should raise an exception here, instead
					-- of silently ignoring the problem.
					--
					n_curr_ou = NULL;
					EXIT;
				END IF;
			END LOOP;
			--
			IF n_curr_ou IS NOT NULL THEN
				RETURN NEXT n_curr_ou;
			END IF;
		ELSE
			--
			-- The permission applies only at a depth greater than the work org unit.
			-- Use connectby() to find all dependent org units at the specified depth.
			--
			FOR n_curr_ou IN
				SELECT ou::INTEGER
				FROM connectby( 
						'actor.org_unit',         -- table name
						'id',                     -- key column
						'parent_ou',              -- recursive foreign key
						n_work_ou::TEXT,          -- id of starting point
						(n_min_depth - n_depth)   -- max depth to search, relative
					)                             --   to starting point
					AS t(
						ou text,            -- dependent org unit
						parent_ou text,     -- (ignore)
						level int           -- depth relative to starting point
					)
				WHERE
					level = n_min_depth - n_depth
			LOOP
				RETURN NEXT n_curr_ou;
			END LOOP;
		END IF;
		--
	END LOOP;
	--
	RETURN;
	--
END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_all_nd(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
--
-- Return a set of all the org units for which a given user has a given
-- permission, granted either directly or through inheritance from a parent
-- org unit.
--
-- The permissions apply to a minimum depth of the org unit hierarchy, and
-- to the subordinates of those org units, for the org unit(s) to which the
-- user is assigned.
--
-- For purposes of this function, the permission.usr_work_ou_map table
-- assigns users to org units.  I.e. we ignore the home_ou column of actor.usr.
--
-- The result set may contain duplicates, which should be eliminated
-- by a DISTINCT clause.
--
DECLARE
	n_head_ou     INTEGER;
	n_child_ou    INTEGER;
BEGIN
	FOR n_head_ou IN
		SELECT DISTINCT * FROM permission.usr_has_perm_at_nd( user_id, perm_code )
	LOOP
		--
		-- The permission applies only at a depth greater than the work org unit.
		-- Use connectby() to find all dependent org units at the specified depth.
		--
		FOR n_child_ou IN
			SELECT ou::INTEGER
			FROM connectby( 
					'actor.org_unit',   -- table name
					'id',               -- key column
					'parent_ou',        -- recursive foreign key
					n_head_ou::TEXT,    -- id of starting point
					0                   -- no limit on search depth
				)
				AS t(
					ou text,            -- dependent org unit
					parent_ou text,     -- (ignore)
					level int           -- (ignore)
				)
		LOOP
			RETURN NEXT n_child_ou;
		END LOOP;
	END LOOP;
	--
	RETURN;
	--
END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION permission.usr_has_perm_at(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
SELECT DISTINCT * FROM permission.usr_has_perm_at_nd( $1, $2 );
$$ LANGUAGE 'sql';


CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_all(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
SELECT DISTINCT * FROM permission.usr_has_perm_at_all_nd( $1, $2 );
$$ LANGUAGE 'sql';



CREATE OR REPLACE FUNCTION vandelay.ingest_items ( import_id BIGINT, attr_def_id BIGINT ) RETURNS SETOF vandelay.import_item AS $$
DECLARE

    owning_lib      TEXT;
    circ_lib        TEXT;
    call_number     TEXT;
    copy_number     TEXT;
    status          TEXT;
    location        TEXT;
    circulate       TEXT;
    deposit         TEXT;
    deposit_amount  TEXT;
    ref             TEXT;
    holdable        TEXT;
    price           TEXT;
    barcode         TEXT;
    circ_modifier   TEXT;
    circ_as_type    TEXT;
    alert_message   TEXT;
    opac_visible    TEXT;
    pub_note        TEXT;
    priv_note       TEXT;

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id;

        -- Build the combined XPath

        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;

        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;

        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;

        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;

        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;

        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;

        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;

        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;

        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;

        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;

        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;

        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;

        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;

        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;

        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;

        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;

        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;


        xpath :=
            owning_lib      || '|' ||
            circ_lib        || '|' ||
            call_number     || '|' ||
            copy_number     || '|' ||
            status          || '|' ||
            location        || '|' ||
            circulate       || '|' ||
            deposit         || '|' ||
            deposit_amount  || '|' ||
            ref             || '|' ||
            holdable        || '|' ||
            price           || '|' ||
            barcode         || '|' ||
            circ_modifier   || '|' ||
            circ_as_type    || '|' ||
            alert_message   || '|' ||
            pub_note        || '|' ||
            priv_note       || '|' ||
            opac_visible;

        -- RAISE NOTICE 'XPath: %', xpath;

        FOR tmp_attr_set IN
                SELECT  *
                  FROM  xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id BIGINT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, opac_vis TEXT )
        LOOP

            tmp_attr_set.pr = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
            tmp_attr_set.dep_amount = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');

            tmp_attr_set.pr := NULLIF( tmp_attr_set.pr, '' );
            tmp_attr_set.dep_amount := NULLIF( tmp_attr_set.dep_amount, '' );

            SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
            SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
            SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT

            SELECT  id INTO attr_set.location
              FROM  asset.copy_location
              WHERE LOWER(name) = LOWER(tmp_attr_set.cl)
                    AND asset.copy_location.owning_lib = COALESCE(attr_set.owning_lib, attr_set.circ_lib); -- INT

            attr_set.circulate      :=
                LOWER( SUBSTRING( tmp_attr_set.circ, 1, 1)) IN ('t','y','1')
                OR LOWER(tmp_attr_set.circ) = 'circulating'; -- BOOL

            attr_set.deposit        :=
                LOWER( SUBSTRING( tmp_attr_set.dep, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.dep) = 'deposit'; -- BOOL

            attr_set.holdable       :=
                LOWER( SUBSTRING( tmp_attr_set.hold, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.hold) = 'holdable'; -- BOOL

            attr_set.opac_visible   :=
                LOWER( SUBSTRING( tmp_attr_set.opac_vis, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.opac_vis) = 'visible'; -- BOOL

            attr_set.ref            :=
                LOWER( SUBSTRING( tmp_attr_set.r, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.r) = 'reference'; -- BOOL

            attr_set.copy_number    := tmp_attr_set.cnum::INT; -- INT,
            attr_set.deposit_amount := tmp_attr_set.dep_amount::NUMERIC(6,2); -- NUMERIC(6,2),
            attr_set.price          := tmp_attr_set.pr::NUMERIC(8,2); -- NUMERIC(8,2),

            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.circ_modifier  := tmp_attr_set.circ_mod; -- TEXT,
            attr_set.circ_as_type   := tmp_attr_set.circ_as; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,

            RETURN NEXT attr_set;

        END LOOP;

    END IF;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors ( INT ) RETURNS SETOF actor.org_unit AS $$
        SELECT  a.*
          FROM  connectby('actor.org_unit'::text,'parent_ou'::text,'id'::text,'name'::text,$1::text,100,'.'::text)
                        AS t(keyid text, parent_keyid text, level int, branch text,pos int)
                JOIN actor.org_unit a ON a.id::text = t.keyid::text
        JOIN actor.org_unit_type tp ON tp.id = a.ou_type
        ORDER BY tp.depth, a.name;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting( setting_name TEXT, org_id INT ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    cur_org INT;
BEGIN
    cur_org := org_id;
    LOOP
        SELECT INTO setting * FROM actor.org_unit_setting WHERE org_unit = cur_org AND name = setting_name;
        IF FOUND THEN
            RETURN NEXT setting;
        END IF;
        SELECT INTO cur_org parent_ou FROM actor.org_unit WHERE id = cur_org;
        EXIT WHEN cur_org IS NULL;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.org_unit_ancestor_setting( TEXT, INT) IS $$
/**
* Search "up" the org_unit tree until we find the first occurrence of an 
* org_unit_setting with the given name.
*/
$$;
 

ALTER TABLE asset.copy_tranparency_map RENAME TO copy_transparency_map;
ALTER TABLE asset.copy_transparency_map RENAME COLUMN tansparency TO transparency;

CREATE TABLE asset.uri (
    id  SERIAL  PRIMARY KEY,
    href    TEXT    NOT NULL,
    label   TEXT,
    use_restriction TEXT,
    active  BOOL    NOT NULL DEFAULT TRUE
);

CREATE TABLE asset.uri_call_number_map (
    id          BIGSERIAL   PRIMARY KEY,
    uri         INT         NOT NULL REFERENCES asset.uri (id),
    call_number INT         NOT NULL REFERENCES asset.call_number (id),
    CONSTRAINT uri_cn_once UNIQUE (uri,call_number)
);
CREATE INDEX asset_uri_call_number_map_cn_idx ON asset.uri_call_number_map (call_number);

-----------------------------

CREATE TABLE container.copy_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);


CREATE TABLE container.copy_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.copy_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

ALTER TABLE container.copy_bucket_item ADD COLUMN pos INT;
CREATE INDEX copy_bucket_item_bucket_idx ON container.copy_bucket_item (bucket);

CREATE TABLE container.copy_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.copy_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);
 
----------------------------- 
 
CREATE TABLE container.call_number_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);
 
ALTER TABLE container.call_number_bucket_item ADD COLUMN pos INT;
CREATE INDEX call_number_bucket_item_bucket_idx ON container.call_number_bucket_item (bucket);

CREATE TABLE container.call_number_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.call_number_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);


CREATE TABLE container.call_number_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.call_number_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

---------------------------
 
CREATE TABLE container.biblio_record_entry_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);


CREATE TABLE container.biblio_record_entry_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

ALTER TABLE container.biblio_record_entry_bucket_item ADD COLUMN pos INT;
CREATE INDEX biblio_record_entry_bucket_item_bucket_idx ON container.biblio_record_entry_bucket_item (bucket);

CREATE TABLE container.biblio_record_entry_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.biblio_record_entry_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

---------------------------
 
CREATE TABLE container.user_bucket_type (
	code	TEXT	PRIMARY KEY,
	label	TEXT	NOT NULL UNIQUE
);
 
CREATE TABLE container.user_bucket_note (
    id      SERIAL      PRIMARY KEY,
    bucket  INT         NOT NULL REFERENCES container.user_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

ALTER TABLE container.user_bucket_item ADD COLUMN pos INT;
CREATE INDEX user_bucket_item_bucket_idx ON container.user_bucket_item (bucket);

CREATE TABLE container.user_bucket_item_note (
    id      SERIAL      PRIMARY KEY,
    item    INT         NOT NULL REFERENCES container.user_bucket_item (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    note    TEXT        NOT NULL
);

-----------------------------

INSERT INTO config.billing_type (name,owner) SELECT DISTINCT billing_type, 1 FROM money.billing WHERE LOWER(billing_type) NOT IN (SELECT LOWER(name) FROM config.billing_type);
ALTER TABLE money.billing ADD COLUMN btype INT;

UPDATE money.billing SET btype = config.billing_type.id FROM config.billing_type WHERE LOWER(config.billing_type.name) = LOWER(money.billing.billing_type);
ALTER TABLE money.billing ALTER COLUMN btype SET NOT NULL;
ALTER TABLE money.billing ADD CONSTRAINT btype_fkey FOREIGN KEY (btype) REFERENCES config.billing_type (id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;


CREATE TABLE money.materialized_billable_xact_summary AS
	SELECT * FROM money.billable_xact_summary;

CREATE INDEX money_mat_summary_id_idx ON money.materialized_billable_xact_summary (id);
CREATE INDEX money_mat_summary_usr_idx ON money.materialized_billable_xact_summary (usr);
CREATE INDEX money_mat_summary_xact_start_idx ON money.materialized_billable_xact_summary (xact_start);

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.mat_summary_create () RETURNS TRIGGER AS $$
BEGIN
	INSERT INTO money.materialized_billable_xact_summary (id, usr, xact_start, xact_finish, total_paid, total_owed, balance_owed, xact_type)
		VALUES ( NEW.id, NEW.usr, NEW.xact_start, NEW.xact_finish, 0.0, 0.0, 0.0, TG_ARGV[0]);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* BEFORE or AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.mat_summary_update () RETURNS TRIGGER AS $$
BEGIN
	UPDATE	money.materialized_billable_xact_summary
	  SET	usr = NEW.usr,
		xact_start = NEW.xact_start,
		xact_finish = NEW.xact_finish
	  WHERE	id = NEW.id;
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.mat_summary_delete () RETURNS TRIGGER AS $$
BEGIN
	DELETE FROM money.materialized_billable_xact_summary WHERE id = OLD.id;
	RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('grocery');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();



/* BEFORE or AFTER trigger */
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_add () RETURNS TRIGGER AS $$
BEGIN
	IF NOT NEW.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed + NEW.amount,
			last_billing_ts = NEW.billing_ts,
			last_billing_note = NEW.note,
			last_billing_type = NEW.billing_type,
			balance_owed = balance_owed + NEW.amount
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_update () RETURNS TRIGGER AS $$
DECLARE
	old_billing	money.billing%ROWTYPE;
	old_voided	money.billing%ROWTYPE;
BEGIN

	SELECT * INTO old_billing FROM money.billing WHERE xact = NEW.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1;
	SELECT * INTO old_voided FROM money.billing WHERE xact = NEW.xact ORDER BY billing_ts DESC LIMIT 1;

	IF NEW.voided AND NOT OLD.voided THEN
		IF OLD.id = old_voided.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_billing_ts = old_billing.billing_ts,
				last_billing_note = old_billing.note,
				last_billing_type = old_billing.billing_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed - NEW.amount,
			balance_owed = balance_owed - NEW.amount
		  WHERE	id = NEW.xact;

	ELSIF NOT NEW.voided AND OLD.voided THEN

		IF OLD.id = old_billing.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_billing_ts = old_billing.billing_ts,
				last_billing_note = old_billing.note,
				last_billing_type = old_billing.billing_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed + NEW.amount,
			balance_owed = balance_owed + NEW.amount
		  WHERE	id = NEW.xact;

	ELSE
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed - (OLD.amount - NEW.amount),
			balance_owed = balance_owed - (OLD.amount - NEW.amount)
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* BEFORE trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_del () RETURNS TRIGGER AS $$
DECLARE
	prev_billing	money.billing%ROWTYPE;
	old_billing	money.billing%ROWTYPE;
BEGIN
	SELECT * INTO prev_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1 OFFSET 1;
	SELECT * INTO old_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1;

	IF OLD.id = old_billing.id THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	last_billing_ts = prev_billing.billing_ts,
			last_billing_note = prev_billing.note,
			last_billing_type = prev_billing.billing_type
		  WHERE	id = OLD.xact;
	END IF;

	IF NOT OLD.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed - OLD.amount,
			balance_owed = balance_owed + OLD.amount
		  WHERE	id = OLD.xact;
	END IF;

	RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_billing_add ();
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_billing_update ();
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_billing_del ();


/* BEFORE or AFTER trigger */
CREATE OR REPLACE FUNCTION money.materialized_summary_payment_add () RETURNS TRIGGER AS $$
BEGIN
	IF NOT NEW.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid + NEW.amount,
			last_payment_ts = NEW.payment_ts,
			last_payment_note = NEW.note,
			last_payment_type = TG_ARGV[0],
			balance_owed = balance_owed - NEW.amount
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_payment_update () RETURNS TRIGGER AS $$
DECLARE
	old_payment	money.payment_view%ROWTYPE;
	old_voided	money.payment_view%ROWTYPE;
BEGIN

	SELECT * INTO old_payment FROM money.payment_view WHERE xact = NEW.xact AND NOT voided ORDER BY payment_ts DESC LIMIT 1;
	SELECT * INTO old_voided FROM money.payment_view WHERE xact = NEW.xact ORDER BY payment_ts DESC LIMIT 1;

	IF NEW.voided AND NOT OLD.voided THEN
		IF OLD.id = old_voided.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_payment_ts = old_payment.payment_ts,
				last_payment_note = old_payment.note,
				last_payment_type = old_payment.payment_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid - NEW.amount,
			balance_owed = balance_owed + NEW.amount
		  WHERE	id = NEW.xact;

	ELSIF NOT NEW.voided AND OLD.voided THEN

		IF OLD.id = old_payment.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_payment_ts = old_payment.payment_ts,
				last_payment_note = old_payment.note,
				last_payment_type = old_payment.payment_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid + NEW.amount,
			balance_owed = balance_owed - NEW.amount
		  WHERE	id = NEW.xact;

	ELSE
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid - (OLD.amount - NEW.amount),
			balance_owed = balance_owed + (OLD.amount - NEW.amount)
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* BEFORE trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_payment_del () RETURNS TRIGGER AS $$
DECLARE
	prev_payment	money.payment_view%ROWTYPE;
	old_payment	money.payment_view%ROWTYPE;
BEGIN
	SELECT * INTO prev_payment FROM money.payment_view WHERE xact = OLD.xact AND NOT voided ORDER BY payment_ts DESC LIMIT 1 OFFSET 1;
	SELECT * INTO old_payment FROM money.payment_view WHERE xact = OLD.xact AND NOT voided ORDER BY payment_ts DESC LIMIT 1;

	IF OLD.id = old_payment.id THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	last_payment_ts = prev_payment.payment_ts,
			last_payment_note = prev_payment.note,
			last_payment_type = prev_payment.payment_type
		  WHERE	id = OLD.xact;
	END IF;

	IF NOT OLD.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid - OLD.amount,
			balance_owed = balance_owed + OLD.amount
		  WHERE	id = OLD.xact;
	END IF;

	RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.bnm_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('bnm_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.bnm_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('bnm_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.bnm_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('bnm_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.forgive_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('forgive_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.forgive_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('forgive_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.forgive_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('forgive_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.work_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('work_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.work_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('work_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.work_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('work_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.credit_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('credit_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.credit_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('credit_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.credit_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('credit_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.goods_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('goods_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.goods_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('goods_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.goods_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('goods_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.bnm_desk_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('bnm_desk_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.bnm_desk_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('bnm_desk_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.bnm_desk_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('bnm_desk_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('bnm_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('bnm_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('bnm_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('bnm_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('bnm_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('bnm_payment');

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.credit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('credit_card_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.credit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('credit_card_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.credit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('credit_card_payment');


CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('circulation');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();

CREATE OR REPLACE VIEW action.billable_circulations AS
 	SELECT	*
 	  FROM	action.circulation
 	  WHERE	xact_finish IS NULL;

CREATE TABLE action.hold_request_cancel_cause (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    UNIQUE
);
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (1,'Untargeted expiration');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (2,'Hold Shelf expiration');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (3,'Patron via phone');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (4,'Patron in person');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (5,'Staff forced');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (6,'Patron via OPAC');
SELECT SETVAL('action.hold_request_cancel_cause_id_seq', 100);
 
ALTER TABLE action.hold_request ADD COLUMN cancel_cause INT;
ALTER TABLE action.hold_request ADD COLUMN cancel_note TEXT;


ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN juvenile_flag BOOL;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN circulate BOOL NOT NULL DEFAULT TRUE;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN duration_rule INT REFERENCES config.rule_circ_duration (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN recurring_fine_rule INT REFERENCES config.rule_recuring_fine (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN max_fine_rule INT REFERENCES config.rule_max_fine (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN script_test TEXT;

ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT ep_once_per_grp_loc_mod_marc;
ALTER TABLE config.circ_matrix_matchpoint
	ADD CONSTRAINT ep_once_per_grp_loc_mod_marc
		UNIQUE (grp, org_unit, circ_modifier, marc_type, marc_form, marc_vr_format, ref_flag, juvenile_flag, usr_age_lower_bound, usr_age_upper_bound, is_renewal);

UPDATE	config.circ_matrix_matchpoint
  SET	duration_rule = config.circ_matrix_ruleset.duration_rule,
	recurring_fine_rule = config.circ_matrix_ruleset.recurring_fine_rule,
	max_fine_rule = config.circ_matrix_ruleset.max_fine_rule
  FROM	config.circ_matrix_ruleset
  WHERE	config.circ_matrix_ruleset.matchpoint = config.circ_matrix_matchpoint.id;

DROP TABLE config.circ_matrix_ruleset;

ALTER TABLE config.circ_matrix_circ_mod_test DROP COLUMN circ_mod;
CREATE TABLE config.circ_matrix_circ_mod_test_map (
    id      SERIAL  PRIMARY KEY,
    circ_mod_test   INT NOT NULL REFERENCES config.circ_matrix_circ_mod_test (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    circ_mod        TEXT    NOT NULL REFERENCES config.circ_modifier (code) ON DELETE CASCADE ON UPDATE CASCADE  DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT cm_once_per_test UNIQUE (circ_mod_test, circ_mod)
);
 
DROP FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL );
CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS config.circ_matrix_matchpoint AS $func$
DECLARE
    current_group    permission.grp_tree%ROWTYPE;
    user_object    actor.usr%ROWTYPE;
    item_object    asset.copy%ROWTYPE;
    rec_descriptor    metabib.rec_descriptor%ROWTYPE;
    current_mp    config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint    config.circ_matrix_matchpoint%ROWTYPE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r JOIN asset.call_number c USING (record) WHERE c.id = item_object.call_number;
    SELECT INTO current_group * FROM permission.grp_tree WHERE id = user_object.profile;

    LOOP
        -- for each potential matchpoint for this ou and group ...
        FOR current_mp IN
            SELECT    m.*
              FROM    config.circ_matrix_matchpoint m
                JOIN actor.org_unit_ancestors( context_ou ) d ON (m.org_unit = d.id)
                LEFT JOIN actor.org_unit_proximity p ON (p.from_org = context_ou AND p.to_org = d.id)
              WHERE    m.grp = current_group.id AND m.active
              ORDER BY    CASE WHEN p.prox        IS NULL THEN 999 ELSE p.prox END,
                    CASE WHEN m.is_renewal = renewal        THEN 128 ELSE 0 END +
                    CASE WHEN m.juvenile_flag    IS NOT NULL THEN 64 ELSE 0 END +
                    CASE WHEN m.circ_modifier    IS NOT NULL THEN 32 ELSE 0 END +
                    CASE WHEN m.marc_type        IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.marc_form        IS NOT NULL THEN 8 ELSE 0 END +
                    CASE WHEN m.marc_vr_format    IS NOT NULL THEN 4 ELSE 0 END +
                    CASE WHEN m.ref_flag        IS NOT NULL THEN 2 ELSE 0 END +
                    CASE WHEN m.usr_age_lower_bound    IS NOT NULL THEN 0.5 ELSE 0 END +
                    CASE WHEN m.usr_age_upper_bound    IS NOT NULL THEN 0.5 ELSE 0 END DESC LOOP

            IF current_mp.circ_modifier IS NOT NULL THEN
                CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier;
            END IF;

            IF current_mp.marc_type IS NOT NULL THEN
                IF item_object.circ_as_type IS NOT NULL THEN
                    CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
                ELSE
                    CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
                END IF;
            END IF;

            IF current_mp.marc_form IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
            END IF;

            IF current_mp.marc_vr_format IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
            END IF;

            IF current_mp.ref_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
            END IF;

            IF current_mp.juvenile_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.juvenile_flag <> user_object.juvenile;
            END IF;

            IF current_mp.usr_age_lower_bound IS NOT NULL THEN
                CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_lower_bound < age(user_object.dob);
            END IF;

            IF current_mp.usr_age_upper_bound IS NOT NULL THEN
                CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_upper_bound > age(user_object.dob);
            END IF;


            -- everything was undefined or matched
            matchpoint = current_mp;

            EXIT WHEN matchpoint.id IS NOT NULL;
        END LOOP;

        EXIT WHEN current_group.parent IS NULL OR matchpoint.id IS NOT NULL;

        SELECT INTO current_group * FROM permission.grp_tree WHERE id = current_group.parent;
    END LOOP;

    RETURN matchpoint;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    user_object        actor.usr%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_status_object    config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result            action.matrix_test_result;
    circ_test        config.circ_matrix_matchpoint%ROWTYPE;
    out_by_circ_mod        config.circ_matrix_circ_mod_test%ROWTYPE;
    circ_mod_map        config.circ_matrix_circ_mod_test_map%ROWTYPE;
    penalty_type         TEXT;
    tmp_grp         INT;
    items_out        INT;
    context_org_list        INT[];
    done            BOOL := FALSE;
BEGIN
    result.success := TRUE;

    -- Fail if the user is BARRED
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Fail if we couldn't find a set of tests
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    IF item_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item isn't in a circulateable status on a non-renewal
    IF NOT renewal AND item_object.status NOT IN ( 0, 7, 8 ) THEN
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    ELSIF renewal AND item_object.status <> 1 THEN
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate because of the shelving location
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;
    IF item_location_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy_location.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, match_item, match_user, renewal);
    result.matchpoint := circ_test.id;

    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( circ_test.org_unit );

    -- Fail if we couldn't find a set of tests
    IF result.matchpoint IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the test is set to hard non-circulating
    IF circ_test.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF renewal THEN
        penalty_type = '%RENEW%';
    ELSE
        penalty_type = '%CIRC%';
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE penalty_type LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the user has too many items with specific circ_modifiers checked out
    FOR out_by_circ_mod IN SELECT * FROM config.circ_matrix_circ_mod_test WHERE matchpoint = circ_test.id LOOP
        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
            JOIN asset.copy cp ON (cp.id = circ.target_copy)
          WHERE circ.usr = match_user
               AND circ_lib IN ( SELECT * FROM explode_array(context_org_list) )
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
            AND cp.circ_modifier IN (SELECT circ_mod FROM config.circ_matrix_circ_mod_test_map WHERE circ_mod_test = out_by_circ_mod.id);
        IF items_out >= out_by_circ_mod.items_out THEN
            result.fail_part := 'config.circ_matrix_circ_mod_test';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END LOOP;

    -- If we passed everything, return the successful matchpoint id
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION actor.calculate_system_penalties( match_user INT, context_org INT ) RETURNS SETOF actor.usr_standing_penalty AS $func$
DECLARE
    user_object         actor.usr%ROWTYPE;
    new_sp_row          actor.usr_standing_penalty%ROWTYPE;
    existing_sp_row     actor.usr_standing_penalty%ROWTYPE;
    collections_fines   permission.grp_penalty_threshold%ROWTYPE;
    max_fines           permission.grp_penalty_threshold%ROWTYPE;
    max_overdue         permission.grp_penalty_threshold%ROWTYPE;
    max_items_out       permission.grp_penalty_threshold%ROWTYPE;
    tmp_grp             INT;
    items_overdue       INT;
    items_out           INT;
    context_org_list    INT[];
    current_fines        NUMERIC(8,2) := 0.0;
    tmp_fines            NUMERIC(8,2);
    tmp_groc            RECORD;
    tmp_circ            RECORD;
    tmp_org             actor.org_unit%ROWTYPE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Max fines
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a high fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 1 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_fines.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 1
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 1;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max overdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many overdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_overdue FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 2 AND org_unit = tmp_org.id;

            IF max_overdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_overdue.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_overdue.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_overdue.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 2
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  INTO items_overdue COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_overdue.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND circ.due_date < NOW()
            AND (circ.stop_fines = 'MAXFINES' OR circ.stop_fines IS NULL);

        IF items_overdue >= max_overdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_overdue.org_unit;
            new_sp_row.standing_penalty := 2;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max out
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many checked out items
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_items_out FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 3 AND org_unit = tmp_org.id;

            IF max_items_out.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_items_out.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;


    -- Fail if the user has too many items checked out
    IF max_items_out.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_items_out.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 3
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_items_out.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
                AND circ.checkin_time IS NULL
                AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL);

           IF items_out >= max_items_out.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_items_out.org_unit;
            new_sp_row.standing_penalty := 3;
            RETURN NEXT new_sp_row;
           END IF;
    END IF;

    -- Start over for collections warning
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a collections-level fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 4 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_fines.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 4
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 4;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;


    RETURN;
END;
$func$ LANGUAGE plpgsql;


ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN juvenile_flag BOOL;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN age_hold_protect_rule INT REFERENCES config.rule_age_hold_protect (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN holdable BOOL NOT NULL DEFAULT TRUE;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN distance_is_from_owner BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN transit_range INT REFERENCES actor.org_unit_type (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN max_holds INT;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN include_frozen_holds BOOL NOT NULL DEFAULT TRUE;
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN stop_blocked_user BOOL NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS INT AS $func$
DECLARE
    current_requestor_group    permission.grp_tree%ROWTYPE;
    root_ou            actor.org_unit%ROWTYPE;
    requestor_object    actor.usr%ROWTYPE;
    user_object        actor.usr%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object        asset.call_number%ROWTYPE;
    rec_descriptor        metabib.rec_descriptor%ROWTYPE;
    current_mp_weight    FLOAT;
    matchpoint_weight    FLOAT;
    tmp_weight        FLOAT;
    current_mp        config.hold_matrix_matchpoint%ROWTYPE;
    matchpoint        config.hold_matrix_matchpoint%ROWTYPE;
BEGIN
    SELECT INTO root_ou * FROM actor.org_unit WHERE parent_ou IS NULL;
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO requestor_object * FROM actor.usr WHERE id = match_requestor;
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r WHERE r.record = item_cn_object.record;
    SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = requestor_object.profile;

    LOOP
        -- for each potential matchpoint for this ou and group ...
        FOR current_mp IN
            SELECT    m.*
              FROM    config.hold_matrix_matchpoint m
              WHERE    m.requestor_grp = current_requestor_group.id AND m.active
              ORDER BY    CASE WHEN m.circ_modifier    IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.juvenile_flag    IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.marc_type        IS NOT NULL THEN 8 ELSE 0 END +
                    CASE WHEN m.marc_form        IS NOT NULL THEN 4 ELSE 0 END +
                    CASE WHEN m.marc_vr_format    IS NOT NULL THEN 2 ELSE 0 END +
                    CASE WHEN m.ref_flag        IS NOT NULL THEN 1 ELSE 0 END DESC LOOP

            current_mp_weight := 5.0;

            IF current_mp.circ_modifier IS NOT NULL THEN
                CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier;
            END IF;

            IF current_mp.marc_type IS NOT NULL THEN
                IF item_object.circ_as_type IS NOT NULL THEN
                    CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
                ELSE
                    CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
                END IF;
            END IF;

            IF current_mp.marc_form IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
            END IF;

            IF current_mp.marc_vr_format IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
            END IF;

            IF current_mp.juvenile_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.juvenile_flag <> user_object.juvenile;
            END IF;

            IF current_mp.ref_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
            END IF;


            -- caclulate the rule match weight
            IF current_mp.item_owning_ou IS NOT NULL AND current_mp.item_owning_ou <> root_ou.id THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_owning_ou, item_cn_object.owning_lib)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF;

            IF current_mp.item_circ_ou IS NOT NULL AND current_mp.item_circ_ou <> root_ou.id THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_circ_ou, item_object.circ_lib)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF;

            IF current_mp.pickup_ou IS NOT NULL AND current_mp.pickup_ou <> root_ou.id THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.pickup_ou, pickup_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF;

            IF current_mp.request_ou IS NOT NULL AND current_mp.request_ou <> root_ou.id THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.request_ou, request_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF;

            IF current_mp.user_home_ou IS NOT NULL AND current_mp.user_home_ou <> root_ou.id THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.user_home_ou, user_object.home_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF;

            -- set the matchpoint if we found the best one
            IF matchpoint_weight IS NULL OR matchpoint_weight > current_mp_weight THEN
                matchpoint = current_mp;
                matchpoint_weight = current_mp_weight;
            END IF;

        END LOOP;

        EXIT WHEN current_requestor_group.parent IS NULL OR matchpoint.id IS NOT NULL;

        SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = current_requestor_group.parent;
    END LOOP;

    RETURN matchpoint.id;
END;
$func$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS
$func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( pickup_ou );

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    result.matchpoint := hold_test.id;
    result.success := TRUE;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE '%HOLD%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP

            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;

        IF item_object.create_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_prox WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_prox WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE SCHEMA acq;


-- Tables


CREATE TABLE acq.currency_type (
    code    TEXT PRIMARY KEY,
    label   TEXT
);

-- Use the ISO 4217 abbreviations for currency codes
INSERT INTO acq.currency_type (code, label) VALUES ('USD','US Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('CAN','Canadian Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('EUR','Euros');

CREATE TABLE acq.exchange_rate (
    id              SERIAL  PRIMARY KEY,
    from_currency   TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    to_currency     TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    ratio           NUMERIC NOT NULL,
    CONSTRAINT exchange_rate_from_to_once UNIQUE (from_currency,to_currency)
);

INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','CAN',1.2);
INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','EUR',0.5);

CREATE TABLE acq.provider (
    id                  SERIAL  PRIMARY KEY,
    name                TEXT    NOT NULL,
    owner               INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    currency_type       TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code                TEXT    UNIQUE,
    holding_tag         TEXT,
    CONSTRAINT provider_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.provider_holding_subfield_map (
    id          SERIAL  PRIMARY KEY,
    provider    INT     NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    NOT NULL, -- barcode, price, etc
    subfield    TEXT    NOT NULL,
    CONSTRAINT name_once_per_provider UNIQUE (provider,name)
);

CREATE TABLE acq.provider_address (
    id      SERIAL  PRIMARY KEY,
    valid       BOOL    NOT NULL DEFAULT TRUE,
    address_type    TEXT,
    provider    INT     NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    street1     TEXT    NOT NULL,
    street2     TEXT,
    city        TEXT    NOT NULL,
    county      TEXT,
    state       TEXT    NOT NULL,
    country     TEXT    NOT NULL,
    post_code   TEXT    NOT NULL
);

CREATE TABLE acq.provider_contact (
    id      SERIAL  PRIMARY KEY,
    provider    INT NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    name    TEXT NULL NULL,
    role    TEXT, -- free-form.. e.g. "our sales guy"
    email   TEXT,
    phone   TEXT
);

CREATE TABLE acq.provider_contact_address (
    id          SERIAL  PRIMARY KEY,
    valid           BOOL    NOT NULL DEFAULT TRUE,
    address_type    TEXT,
    contact         INT     NOT NULL REFERENCES acq.provider_contact (id) DEFERRABLE INITIALLY DEFERRED,
    street1         TEXT    NOT NULL,
    street2         TEXT,
    city            TEXT    NOT NULL,
    county          TEXT,
    state           TEXT    NOT NULL,
    country         TEXT    NOT NULL,
    post_code       TEXT    NOT NULL
);


CREATE TABLE acq.funding_source (
    id      SERIAL  PRIMARY KEY,
    name        TEXT    NOT NULL,
    owner       INT NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    currency_type   TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code        TEXT    UNIQUE,
    CONSTRAINT funding_source_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.funding_source_credit (
    id  SERIAL  PRIMARY KEY,
    funding_source    INT     NOT NULL REFERENCES acq.funding_source (id) DEFERRABLE INITIALLY DEFERRED,
    amount  NUMERIC NOT NULL,
    note    TEXT
);

CREATE TABLE acq.fund (
    id              SERIAL  PRIMARY KEY,
    org             INT     NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT    NOT NULL,
    year            INT     NOT NULL DEFAULT EXTRACT( YEAR FROM NOW() ),
    currency_type   TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code            TEXT    UNIQUE,
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year)
);

CREATE TABLE acq.fund_debit (
    id          SERIAL  PRIMARY KEY,
    fund            INT     NOT NULL REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
    origin_amount       NUMERIC NOT NULL,  -- pre-exchange-rate amount
    origin_currency_type    TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    amount          NUMERIC NOT NULL,
    encumbrance     BOOL    NOT NULL DEFAULT TRUE,
    debit_type      TEXT    NOT NULL,
    xfer_destination    INT REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
    create_time     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE acq.fund_allocation (
    id          SERIAL  PRIMARY KEY,
    funding_source        INT     NOT NULL REFERENCES acq.funding_source (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    fund        INT     NOT NULL REFERENCES acq.fund (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    amount      NUMERIC,
    percent     NUMERIC CHECK (percent IS NULL OR percent BETWEEN 0.0 AND 100.0),
    allocator   INT NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    note        TEXT,
    create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT allocation_amount_or_percent CHECK ((percent IS NULL AND amount IS NOT NULL) OR (percent IS NOT NULL AND amount IS NULL))
);


CREATE TABLE acq.picklist (
    id      SERIAL              PRIMARY KEY,
    owner       INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    creator         INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    editor          INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    org_unit    INT             NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    name        TEXT                NOT NULL,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    edit_time   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    CONSTRAINT name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.purchase_order (
    id      SERIAL              PRIMARY KEY,
    owner       INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    creator         INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    editor          INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    ordering_agency INT             NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    edit_time   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    provider    INT             NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    state       TEXT                NOT NULL DEFAULT 'new'
);
CREATE INDEX po_owner_idx ON acq.purchase_order (owner);
CREATE INDEX po_provider_idx ON acq.purchase_order (provider);
CREATE INDEX po_state_idx ON acq.purchase_order (state);

CREATE TABLE acq.po_note (
    id      SERIAL              PRIMARY KEY,
    purchase_order  INT             NOT NULL REFERENCES acq.purchase_order (id) DEFERRABLE INITIALLY DEFERRED,
    creator     INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    editor      INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    edit_time   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    value       TEXT                NOT NULL
);
CREATE INDEX po_note_po_idx ON acq.po_note (purchase_order);

CREATE TABLE acq.lineitem (
    id                  BIGSERIAL                   PRIMARY KEY,
    creator             INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    editor              INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    selector            INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    provider            INT                         REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    purchase_order      INT                         REFERENCES acq.purchase_order (id) DEFERRABLE INITIALLY DEFERRED,
    picklist            INT                         REFERENCES acq.picklist (id) DEFERRABLE INITIALLY DEFERRED,
    expected_recv_time  TIMESTAMP WITH TIME ZONE,
    create_time         TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    edit_time           TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    marc                TEXT                        NOT NULL,
    eg_bib_id           INT                         REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
    source_label        TEXT,
    item_count          INT                         NOT NULL DEFAULT 0,
    state               TEXT                        NOT NULL DEFAULT 'new',
    CONSTRAINT picklist_or_po CHECK (picklist IS NOT NULL OR purchase_order IS NOT NULL)
);
CREATE INDEX li_po_idx ON acq.lineitem (purchase_order);
CREATE INDEX li_pl_idx ON acq.lineitem (picklist);

CREATE TABLE acq.lineitem_note (
    id      SERIAL              PRIMARY KEY,
    lineitem    INT             NOT NULL REFERENCES acq.lineitem (id) DEFERRABLE INITIALLY DEFERRED,
    creator     INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    editor      INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    edit_time   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    value       TEXT                NOT NULL
);
CREATE INDEX li_note_li_idx ON acq.lineitem_note (lineitem);

CREATE TABLE acq.lineitem_detail (
    id          BIGSERIAL   PRIMARY KEY,
    lineitem    INT         NOT NULL REFERENCES acq.lineitem (id) DEFERRABLE INITIALLY DEFERRED,
    fund        INT         REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
    fund_debit  INT         REFERENCES acq.fund_debit (id) DEFERRABLE INITIALLY DEFERRED,
    eg_copy_id  BIGINT      REFERENCES asset.copy (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    barcode     TEXT,
    cn_label    TEXT,
    note        TEXT,
    collection_code TEXT,
    circ_modifier   TEXT    REFERENCES config.circ_modifier (code) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    owning_lib  INT         REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    location    INT         REFERENCES asset.copy_location (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    recv_time   TIMESTAMP WITH TIME ZONE
);

CREATE INDEX li_detail_li_idx ON acq.lineitem_detail (lineitem);

CREATE TABLE acq.lineitem_attr_definition (
    id      BIGSERIAL   PRIMARY KEY,
    code        TEXT        NOT NULL,
    description TEXT        NOT NULL,
    remove      TEXT        NOT NULL DEFAULT '',
    ident       BOOL        NOT NULL DEFAULT FALSE
);

CREATE TABLE acq.lineitem_marc_attr_definition (
    id      BIGINT  PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
    xpath       TEXT        NOT NULL
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_provider_attr_definition (
    id      BIGINT  PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
    xpath       TEXT        NOT NULL,
    provider    INT NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_generated_attr_definition (
    id      BIGINT  PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
    xpath       TEXT        NOT NULL
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_usr_attr_definition (
    id      BIGINT  PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
    usr     INT NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_local_attr_definition (
    id      BIGINT  PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq')
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_attr (
    id      BIGSERIAL   PRIMARY KEY,
    definition  BIGINT      NOT NULL,
    lineitem    BIGINT      NOT NULL REFERENCES acq.lineitem (id) DEFERRABLE INITIALLY DEFERRED,
    attr_type   TEXT        NOT NULL,
    attr_name   TEXT        NOT NULL,
    attr_value  TEXT        NOT NULL
);

CREATE INDEX li_attr_li_idx ON acq.lineitem_attr (lineitem);
CREATE INDEX li_attr_value_idx ON acq.lineitem_attr (attr_value);
CREATE INDEX li_attr_definition_idx ON acq.lineitem_attr (definition);


-- Seed data


INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('title','Title of work','//*[@tag="245"]/*[contains("abcmnopr",@code)]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('author','Author of work','//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('language','Language of work','//*[@tag="240"]/*[@code="l"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('pagination','Pagination','//*[@tag="300"]/*[@code="a"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('isbn','ISBN','//*[@tag="020"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('issn','ISSN','//*[@tag="022"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('price','Price','//*[@tag="020" or @tag="022"]/*[@code="c"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('identifier','Identifier','//*[@tag="001"]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('publisher','Publisher','//*[@tag="260"]/*[@code="b"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('pubdate','Publication Date','//*[@tag="260"]/*[@code="c"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('edition','Edition','//*[@tag="250"]/*[@code="a"][1]');

INSERT INTO acq.lineitem_local_attr_definition ( code, description ) VALUES ('estimated_price', 'Estimated Price');


CREATE TABLE acq.distribution_formula (
    id      SERIAL PRIMARY KEY,
    owner   INT NOT NULL
            REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
    name    TEXT NOT NULL,
    skip_count  INT NOT NULL DEFAULT 0,
    CONSTRAINT acqdf_name_once_per_owner UNIQUE (name, owner)
);

CREATE TABLE acq.distribution_formula_entry (
    id          SERIAL PRIMARY KEY,
    formula     INTEGER NOT NULL REFERENCES acq.distribution_formula(id)
                ON DELETE CASCADE
                DEFERRABLE INITIALLY DEFERRED,
    position    INTEGER NOT NULL,
    item_count  INTEGER NOT NULL,
    owning_lib  INTEGER REFERENCES actor.org_unit(id)
                DEFERRABLE INITIALLY DEFERRED,
    location    INTEGER REFERENCES asset.copy_location(id),
    CONSTRAINT acqdfe_lib_once_per_formula UNIQUE( formula, position ),
    CONSTRAINT acqdfe_must_be_somewhere
                CHECK( owning_lib IS NOT NULL OR location IS NOT NULL )
);

CREATE TABLE acq.fund_tag (
    id      SERIAL PRIMARY KEY,
    owner   INT NOT NULL
            REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
    name    TEXT NOT NULL,
    CONSTRAINT acqft_tag_once_per_owner UNIQUE (name, owner)
);

CREATE TABLE acq.fund_tag_map (
    id          SERIAL PRIMARY KEY,
    fund        INTEGER NOT NULL REFERENCES acq.fund(id)
                DEFERRABLE INITIALLY DEFERRED,
    tag         INTEGER REFERENCES acq.fund_tag(id)
                ON DELETE CASCADE
                DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT acqftm_fund_once_per_tag UNIQUE( fund, tag )
);

-- Functions

CREATE TYPE acq.flat_lineitem_holding_subfield AS (lineitem int, holding int, subfield text, data text);
CREATE OR REPLACE FUNCTION acq.extract_holding_attr_table (lineitem int, tag text) RETURNS SETOF acq.flat_lineitem_holding_subfield AS $$
DECLARE
    counter INT;
    lida    acq.flat_lineitem_holding_subfield%ROWTYPE;
BEGIN

    SELECT  COUNT(*) INTO counter
      FROM  xpath_table(
                'id',
                'marc',
                'acq.lineitem',
                '//*[@tag="' || tag || '"]',
                'id=' || lineitem
            ) as t(i int,c text);

    FOR i IN 1 .. counter LOOP
        FOR lida IN
            SELECT  *
              FROM  (   SELECT  id,i,t,v
                          FROM  xpath_table(
                                    'id',
                                    'marc',
                                    'acq.lineitem',
                                    '//*[@tag="' || tag || '"][position()=' || i || ']/*/@code|' ||
                                        '//*[@tag="' || tag || '"][position()=' || i || ']/*[@code]',
                                    'id=' || lineitem
                                ) as t(id int,t text,v text)
                    )x
        LOOP
            RETURN NEXT lida;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE acq.flat_lineitem_detail AS (lineitem int, holding int, attr text, data text);
CREATE OR REPLACE FUNCTION acq.extract_provider_holding_data ( lineitem_i int ) RETURNS SETOF acq.flat_lineitem_detail AS $$
DECLARE
    prov_i  INT;
    tag_t   TEXT;
    lida    acq.flat_lineitem_detail%ROWTYPE;
BEGIN
    SELECT provider INTO prov_i FROM acq.lineitem WHERE id = lineitem_i;
    IF NOT FOUND THEN RETURN; END IF;

    SELECT holding_tag INTO tag_t FROM acq.provider WHERE id = prov_i;
    IF NOT FOUND OR tag_t IS NULL THEN RETURN; END IF;

    FOR lida IN
        SELECT  lineitem_i,
                h.holding,
                a.name,
                h.data
          FROM  acq.extract_holding_attr_table( lineitem_i, tag_t ) h
                JOIN acq.provider_holding_subfield_map a USING (subfield)
          WHERE a.provider = prov_i
    LOOP
        RETURN NEXT lida;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;

-- select * from acq.extract_provider_holding_data(699);

CREATE OR REPLACE FUNCTION public.extract_acq_marc_field ( BIGINT, TEXT, TEXT) RETURNS TEXT AS $$
    SELECT public.extract_marc_field('acq.lineitem', $1, $2, $3);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.ingest_acq_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value       TEXT;
    atype       TEXT;
    prov        INT;
    adef        RECORD;
    xpath_string    TEXT;
BEGIN
    FOR adef IN SELECT *,tableoid FROM acq.lineitem_attr_definition LOOP

        SELECT relname::TEXT INTO atype FROM pg_class WHERE oid = adef.tableoid;

        IF (atype NOT IN ('lineitem_usr_attr_definition','lineitem_local_attr_definition')) THEN
            IF (atype = 'lineitem_provider_attr_definition') THEN
                SELECT provider INTO prov FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
                CONTINUE WHEN NEW.provider IS NULL OR prov <> NEW.provider;
            END IF;

            IF (atype = 'lineitem_provider_attr_definition') THEN
                SELECT xpath INTO xpath_string FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
            ELSIF (atype = 'lineitem_marc_attr_definition') THEN
                SELECT xpath INTO xpath_string FROM acq.lineitem_marc_attr_definition WHERE id = adef.id;
            ELSIF (atype = 'lineitem_generated_attr_definition') THEN
                SELECT xpath INTO xpath_string FROM acq.lineitem_generated_attr_definition WHERE id = adef.id;
            END IF;

            SELECT extract_acq_marc_field(id, xpath_string, adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;

            IF (value IS NOT NULL AND value <> '') THEN
                INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
                    VALUES (NEW.id, adef.id, atype, adef.code, value);
            END IF;

        END IF;

    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION public.cleanup_acq_marc ( ) RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        DELETE FROM acq.lineitem_attr
                WHERE lineitem = OLD.id AND attr_type IN ('lineitem_provider_attr_definition', 'lineitem_marc_attr_definition','lineitem_generated_attr_definition');
        RETURN NEW;
    ELSE
        DELETE FROM acq.lineitem_attr WHERE lineitem = OLD.id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER cleanup_lineitem_trigger
    BEFORE UPDATE OR DELETE ON acq.lineitem
    FOR EACH ROW EXECUTE PROCEDURE public.cleanup_acq_marc();

CREATE TRIGGER ingest_lineitem_trigger
    AFTER INSERT OR UPDATE ON acq.lineitem
    FOR EACH ROW EXECUTE PROCEDURE public.ingest_acq_marc();

CREATE OR REPLACE FUNCTION acq.exchange_ratio ( from_ex TEXT, to_ex TEXT ) RETURNS NUMERIC AS $$
DECLARE
    rat NUMERIC;
BEGIN
    IF from_ex = to_ex THEN
        RETURN 1.0;
    END IF;

    SELECT ratio INTO rat FROM acq.exchange_rate WHERE from_currency = from_ex AND to_currency = to_ex;

    IF FOUND THEN
        RETURN rat;
    ELSE
        SELECT ratio INTO rat FROM acq.exchange_rate WHERE from_currency = to_ex AND to_currency = from_ex;
        IF FOUND THEN
            RETURN 1.0/rat;
        END IF;
    END IF;

    RETURN NULL;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION acq.exchange_ratio ( TEXT, TEXT, NUMERIC ) RETURNS NUMERIC AS $$
    SELECT $3 * acq.exchange_ratio($1, $2);
$$ LANGUAGE SQL;

CREATE OR REPLACE VIEW acq.funding_source_credit_total AS
    SELECT  funding_source,
            SUM(amount) AS amount
      FROM  acq.funding_source_credit
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_allocation_total AS
    SELECT  funding_source,
            SUM(amount)::NUMERIC(100,2) AS amount
      FROM (
            SELECT  funding_source,
                    SUM(a.amount)::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
              WHERE a.percent IS NULL
              GROUP BY 1
                            UNION ALL
            SELECT  funding_source,
                    SUM( (SELECT SUM(amount) FROM acq.funding_source_credit c WHERE c.funding_source = a.funding_source) * (a.percent/100.0) )::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
              WHERE a.amount IS NULL
              GROUP BY 1
        ) x
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_balance AS
    SELECT  COALESCE(c.funding_source, a.funding_source) AS funding_source,
            SUM(COALESCE(c.amount,0.0) - COALESCE(a.amount,0.0))::NUMERIC(100,2) AS amount
      FROM  acq.funding_source_credit_total c
            FULL JOIN acq.funding_source_allocation_total a USING (funding_source)
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_allocation_total AS
    SELECT  fund,
            SUM(amount)::NUMERIC(100,2) AS amount
      FROM (
            SELECT  fund,
                    SUM(a.amount * acq.exchange_ratio(s.currency_type, f.currency_type))::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
                    JOIN acq.fund f ON (a.fund = f.id)
                    JOIN acq.funding_source s ON (a.funding_source = s.id)
              WHERE a.percent IS NULL
              GROUP BY 1
                            UNION ALL
            SELECT  fund,
                    SUM( (SELECT SUM(amount) FROM acq.funding_source_credit c WHERE c.funding_source = a.funding_source) * acq.exchange_ratio(s.currency_type, f.currency_type) * (a.percent/100.0) )::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
                    JOIN acq.fund f ON (a.fund = f.id)
                    JOIN acq.funding_source s ON (a.funding_source = s.id)
              WHERE a.amount IS NULL
              GROUP BY 1
        ) x
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_debit_total AS
    SELECT  id AS fund,
            encumbrance,
            SUM(amount) AS amount
      FROM  acq.fund_debit
      GROUP BY 1,2;

CREATE OR REPLACE VIEW acq.fund_encumbrance_total AS
    SELECT  fund,
            SUM(amount) AS amount
      FROM  acq.fund_debit_total
      WHERE encumbrance IS TRUE
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_spent_total AS
    SELECT  fund,
            SUM(amount) AS amount
      FROM  acq.fund_debit_total
      WHERE encumbrance IS FALSE
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_combined_balance AS
    SELECT  c.fund,
            c.amount - COALESCE(d.amount,0.0) AS amount
      FROM  acq.fund_allocation_total c
            LEFT JOIN acq.fund_debit_total d USING (fund);

CREATE OR REPLACE VIEW acq.fund_spent_balance AS
    SELECT  c.fund,
            c.amount - COALESCE(d.amount,0.0) AS amount
      FROM  acq.fund_allocation_total c
            LEFT JOIN acq.fund_spent_total d USING (fund);

CREATE SCHEMA serial;

CREATE TABLE serial.record_entry (
    id      BIGSERIAL   PRIMARY KEY,
    record      BIGINT      REFERENCES biblio.record_entry (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    owning_lib  INT     NOT NULL DEFAULT 1 REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    creator     INT     NOT NULL DEFAULT 1,
    editor      INT     NOT NULL DEFAULT 1,
    source      INT,
    create_date TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    edit_date   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    active      BOOL        NOT NULL DEFAULT TRUE,
    deleted     BOOL        NOT NULL DEFAULT FALSE,
    marc        TEXT        NOT NULL,
    last_xact_id    TEXT        NOT NULL
);
CREATE INDEX serial_record_entry_creator_idx ON serial.record_entry ( creator );
CREATE INDEX serial_record_entry_editor_idx ON serial.record_entry ( editor );
CREATE INDEX serial_record_entry_owning_lib_idx ON serial.record_entry ( owning_lib, deleted );

CREATE TABLE serial.subscription (
    id      SERIAL  PRIMARY KEY,
    callnumber  BIGINT  REFERENCES asset.call_number (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    uri     INT REFERENCES asset.uri (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    start_date  DATE    NOT NULL,
    end_date    DATE    -- interpret NULL as current subscription 
);

CREATE TABLE serial.binding_unit (
    id      SERIAL  PRIMARY KEY,
    subscription    INT NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    label       TEXT    NOT NULL,
    CONSTRAINT bu_label_once_per_sub UNIQUE (subscription, label)
);

CREATE TABLE serial.issuance (
    id      SERIAL  PRIMARY KEY,
    subscription    INT NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    target_copy BIGINT  REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    location    BIGINT  REFERENCES asset.copy_location(id) DEFERRABLE INITIALLY DEFERRED,
    binding_unit    INT REFERENCES serial.binding_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    label       TEXT
);

CREATE TABLE serial.bib_summary (
    id          SERIAL  PRIMARY KEY,
    subscription        INT UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    generated_coverage  TEXT    NOT NULL,
    textual_holdings    TEXT
);

CREATE TABLE serial.sup_summary (
    id          SERIAL  PRIMARY KEY,
    subscription        INT UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    generated_coverage  TEXT    NOT NULL,
    textual_holdings    TEXT
);

CREATE TABLE serial.index_summary (
    id          SERIAL  PRIMARY KEY,
    subscription        INT UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    generated_coverage  TEXT    NOT NULL,
    textual_holdings    TEXT
);


CREATE OR REPLACE FUNCTION search.staged_fts (

    param_search_ou INT,
    param_depth     INT,
    param_searches  TEXT, -- JSON hash, to be turned into a resultset via search.parse_search_args
    param_statuses  INT[],
    param_locations INT[],
    param_audience  TEXT[],
    param_language  TEXT[],
    param_lit_form  TEXT[],
    param_types     TEXT[],
    param_forms     TEXT[],
    param_vformats  TEXT[],
    param_bib_level TEXT[],
    param_before    TEXT,
    param_after     TEXT,
    param_during    TEXT,
    param_between   TEXT[],
    param_pref_lang TEXT,
    param_pref_lang_multiplier REAL,
    param_sort      TEXT,
    param_sort_desc BOOL,
    metarecord      BOOL,
    staff           BOOL,
    param_rel_limit INT,
    param_chk_limit INT,
    param_skip_chk  INT

) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    query_part          search.search_args%ROWTYPE;
    phrase_query_part   search.search_args%ROWTYPE;
    rank_adjust_id      INT;
    core_rel_limit      INT;
    core_chk_limit      INT;
    core_skip_chk       INT;
    rank_adjust         search.relevance_adjustment%ROWTYPE;
    query_table         TEXT;
    tmp_text            TEXT;
    tmp_int             INT;
    current_rank        TEXT;
    ranks               TEXT[] := '{}';
    query_table_alias   TEXT;
    from_alias_array    TEXT[] := '{}';
    used_ranks          TEXT[] := '{}';
    mb_field            INT;
    mb_field_list       INT[];
    search_org_list     INT[];
    select_clause       TEXT := 'SELECT';
    from_clause         TEXT := ' FROM  metabib.metarecord_source_map m JOIN metabib.rec_descriptor mrd ON (m.source = mrd.record) ';
    where_clause        TEXT := ' WHERE 1=1 ';
    mrd_used            BOOL := FALSE;
    sort_desc           BOOL := FALSE;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;
    vis_limit_query     TEXT;
    inner_where_clause  TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    core_rel_limit := COALESCE( param_rel_limit, 25000 );
    core_chk_limit := COALESCE( param_chk_limit, 1000 );
    core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF metarecord THEN
        select_clause := select_clause || ' m.metarecord as id, array_accum(distinct m.source) as records,';
    ELSE
        select_clause := select_clause || ' m.source as id, array_accum(distinct m.source) as records,';
    END IF;

    -- first we need to construct the base query
    FOR query_part IN SELECT * FROM search.parse_search_args(param_searches) WHERE term_type = 'fts_query' LOOP

        inner_where_clause := 'index_vector @@ ' || query_part.term;

        IF query_part.field_name IS NOT NULL THEN

           SELECT  id INTO mb_field
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class
                   AND name = query_part.field_name;

            IF FOUND THEN
                inner_where_clause := inner_where_clause ||
                    ' AND ' || 'field = ' || mb_field;
            END IF;

        END IF;

        -- moving on to the rank ...
        SELECT  * INTO query_part
          FROM  search.parse_search_args(param_searches)
          WHERE term_type = 'fts_rank'
                AND table_alias = query_part.table_alias;

        current_rank := query_part.term || ' * ' || query_part.table_alias || '_weight.weight';

        IF query_part.field_name IS NOT NULL THEN

           SELECT  array_accum(distinct id) INTO mb_field_list
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class
                   AND name = query_part.field_name;

        ELSE

           SELECT  array_accum(distinct id) INTO mb_field_list
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class;

        END IF;

        FOR rank_adjust IN SELECT * FROM search.relevance_adjustment WHERE active AND field IN ( SELECT * FROM search.explode_array( mb_field_list ) ) LOOP

            IF NOT rank_adjust.bump_type = ANY (used_ranks) THEN

                IF rank_adjust.bump_type = 'first_word' THEN
                    SELECT  term INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word'
                      ORDER BY id
                      LIMIT 1;

                    tmp_text := query_part.table_alias || '.value ILIKE ' || quote_literal( tmp_text || '%' );

                ELSIF rank_adjust.bump_type = 'word_order' THEN
                    SELECT  array_to_string( array_accum( term ), '%' ) INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word';

                    tmp_text := query_part.table_alias || '.value ILIKE ' || quote_literal( '%' || tmp_text || '%' );

                ELSIF rank_adjust.bump_type = 'full_match' THEN
                    SELECT  array_to_string( array_accum( term ), E'\\s+' ) INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word';

                    tmp_text := query_part.table_alias || '.value  ~ ' || quote_literal( '^' || tmp_text || E'\\W*$' );

                END IF;


                IF tmp_text IS NOT NULL THEN
                    current_rank := current_rank || ' * ( CASE WHEN ' || tmp_text ||
                        ' THEN ' || rank_adjust.multiplier || '::REAL ELSE 1.0 END )';
                END IF;

                used_ranks := array_append( used_ranks, rank_adjust.bump_type );

            END IF;

        END LOOP;

        ranks := array_append( ranks, current_rank );
        used_ranks := '{}';

        FOR phrase_query_part IN
            SELECT  *
              FROM  search.parse_search_args(param_searches)
              WHERE term_type = 'phrase'
                    AND table_alias = query_part.table_alias LOOP

            tmp_text := replace( phrase_query_part.term, '*', E'\\*' );
            tmp_text := replace( tmp_text, '?', E'\\?' );
            tmp_text := replace( tmp_text, '+', E'\\+' );
            tmp_text := replace( tmp_text, '|', E'\\|' );
            tmp_text := replace( tmp_text, '(', E'\\(' );
            tmp_text := replace( tmp_text, ')', E'\\)' );
            tmp_text := replace( tmp_text, '[', E'\\[' );
            tmp_text := replace( tmp_text, ']', E'\\]' );

            inner_where_clause := inner_where_clause || ' AND ' || 'value  ~* ' || quote_literal( E'(^|\\W+)' || regexp_replace(tmp_text, E'\\s+',E'\\\\s+','g') || E'(\\W+|\$)' );

        END LOOP;

        query_table := search.pick_table(query_part.field_class);

        from_clause := from_clause ||
            ' JOIN ( SELECT * FROM ' || query_table || ' WHERE ' || inner_where_clause ||
                    CASE WHEN core_rel_limit > 0 THEN ' LIMIT ' || core_rel_limit::TEXT ELSE '' END || ' ) AS ' || query_part.table_alias ||
                ' ON ( m.source = ' || query_part.table_alias || '.source )' ||
            ' JOIN config.metabib_field AS ' || query_part.table_alias || '_weight' ||
                ' ON ( ' || query_part.table_alias || '.field = ' || query_part.table_alias || '_weight.id  AND  ' || query_part.table_alias || '_weight.search_field)';

        from_alias_array := array_append(from_alias_array, query_part.table_alias);

    END LOOP;

    IF param_pref_lang IS NOT NULL AND param_pref_lang_multiplier IS NOT NULL THEN
        current_rank := ' CASE WHEN mrd.item_lang = ' || quote_literal( param_pref_lang ) ||
            ' THEN ' || param_pref_lang_multiplier || '::REAL ELSE 1.0 END ';

        -- ranks := array_append( ranks, current_rank );
    END IF;

    current_rank := ' AVG( ( (' || array_to_string( ranks, ') + (' ) || ') ) * ' || current_rank || ' ) ';
    select_clause := select_clause || current_rank || ' AS rel,';

    sort_desc = param_sort_desc;

    IF param_sort = 'pubdate' THEN

        tmp_text := '999999';
        IF param_sort_desc THEN tmp_text := '0'; END IF;

        current_rank := $$ COALESCE( FIRST(NULLIF(REGEXP_REPLACE(mrd.date1, E'\\D+', '9', 'g'),'')), $$ || quote_literal(tmp_text) || $$ )::INT $$;

    ELSIF param_sort = 'title' THEN

        tmp_text := 'zzzzzz';
        IF param_sort_desc THEN tmp_text := '    '; END IF;

        current_rank := $$
            ( COALESCE( FIRST ((
                SELECT  LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\d+'),'0')::INT + 1 ))
                  FROM  metabib.full_rec frt
                  WHERE frt.record = m.source
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )),$$ || quote_literal(tmp_text) || $$))
        $$;

    ELSIF param_sort = 'author' THEN

        tmp_text := 'zzzzzz';
        IF param_sort_desc THEN tmp_text := '    '; END IF;

        current_rank := $$
            ( COALESCE( FIRST ((
                SELECT  LTRIM(fra.value)
                  FROM  metabib.full_rec fra
                  WHERE fra.record = m.source
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
            )),$$ || quote_literal(tmp_text) || $$))
        $$;

    ELSIF param_sort = 'create_date' THEN
            current_rank := $$( FIRST (( SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )$$;
    ELSIF param_sort = 'edit_date' THEN
            current_rank := $$( FIRST (( SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )$$;
    ELSE
        sort_desc := NOT COALESCE(param_sort_desc, FALSE);
    END IF;

    select_clause := select_clause || current_rank || ' AS rank';

    -- now add the other qualifiers
    IF param_audience IS NOT NULL AND array_upper(param_audience, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.audience IN ('$$ || array_to_string(param_audience, $$','$$) || $$') $$;
    END IF;

    IF param_language IS NOT NULL AND array_upper(param_language, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_lang IN ('$$ || array_to_string(param_language, $$','$$) || $$') $$;
    END IF;

    IF param_lit_form IS NOT NULL AND array_upper(param_lit_form, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.lit_form IN ('$$ || array_to_string(param_lit_form, $$','$$) || $$') $$;
    END IF;

    IF param_types IS NOT NULL AND array_upper(param_types, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_type IN ('$$ || array_to_string(param_types, $$','$$) || $$') $$;
    END IF;

    IF param_forms IS NOT NULL AND array_upper(param_forms, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_form IN ('$$ || array_to_string(param_forms, $$','$$) || $$') $$;
    END IF;

    IF param_vformats IS NOT NULL AND array_upper(param_vformats, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.vr_format IN ('$$ || array_to_string(param_vformats, $$','$$) || $$') $$;
    END IF;

    IF param_bib_level IS NOT NULL AND array_upper(param_bib_level, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.bib_level IN ('$$ || array_to_string(param_bib_level, $$','$$) || $$') $$;
    END IF;

    IF param_before IS NOT NULL AND param_before <> '' THEN
        where_clause = where_clause || $$ AND mrd.date1 <= $$ || quote_literal(param_before) || ' ';
    END IF;

    IF param_after IS NOT NULL AND param_after <> '' THEN
        where_clause = where_clause || $$ AND mrd.date1 >= $$ || quote_literal(param_after) || ' ';
    END IF;

    IF param_during IS NOT NULL AND param_during <> '' THEN
        where_clause = where_clause || $$ AND $$ || quote_literal(param_during) || $$ BETWEEN mrd.date1 AND mrd.date2 $$;
    END IF;

    IF param_between IS NOT NULL AND array_upper(param_between, 1) > 1 THEN
        where_clause = where_clause || $$ AND mrd.date1 BETWEEN '$$ || array_to_string(param_between, $$' AND '$$) || $$' $$;
    END IF;

    core_rel_query := select_clause || from_clause || where_clause ||
                        ' GROUP BY 1 ORDER BY 4' || CASE WHEN sort_desc THEN ' DESC' ELSE ' ASC' END || ';';
    --RAISE NOTICE 'Base Query:  %', core_rel_query;

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE core_rel_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;


        IF total_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % total, % checked so far ... ', total_count, check_count;
        END IF;

        IF core_chk_limit > 0 AND total_count - core_skip_chk + 1 >= core_chk_limit THEN
            total_count := total_count + 1;
            CONTINUE;
        END IF;

        total_count := total_count + 1;

        CONTINUE WHEN param_skip_chk IS NOT NULL and total_count < param_skip_chk;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        PERFORM 1
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                JOIN asset.uri uri ON (map.uri = uri.id)
          WHERE NOT cn.deleted
                AND cn.label = '##URI##'
                AND uri.active
                AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
          LIMIT 1;

        IF FOUND THEN
            -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all status-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all copy_location-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                    JOIN asset.copy_location cl ON (cp.location = cl.id)
                    JOIN config.copy_status cs ON (cp.status = cs.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cs.opac_visible
                    AND cl.opac_visible
                    AND cp.opac_visible
                    AND a.opac_visible
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                    JOIN asset.copy_location cl ON (cp.location = cl.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  asset.call_number cn
                  WHERE cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF FOUND THEN
                    -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;


CREATE TABLE config.idl_field_doc (
    id              BIGSERIAL   PRIMARY KEY,
    fm_class        TEXT        NOT NULL,
    field           TEXT        NOT NULL,
    owner           INT         NOT NULL    REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    string          TEXT        NOT NULL
);
CREATE UNIQUE INDEX idl_field_doc_identity ON config.idl_field_doc (fm_class,field,owner);


INSERT INTO config.xml_transform VALUES ( 'mods33', 'http://www.loc.gov/mods/v3', 'mods33', '');
 
INSERT INTO container.copy_bucket_type (code,label) VALUES ('misc', 'Miscellaneous');
INSERT INTO container.copy_bucket_type (code,label) VALUES ('staff_client', 'General Staff Client container');
INSERT INTO container.call_number_bucket_type (code,label) VALUES ('misc', 'Miscellaneous');
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('misc', 'Miscellaneous');
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('staff_client', 'General Staff Client container');
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('bookbag', 'Book Bag');
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('reading_list', 'Reading List');

INSERT INTO container.user_bucket_type (code,label) VALUES ('misc', 'Miscellaneous');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks', 'Friends');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:pub_book_bags.view', 'List Published Book Bags');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:pub_book_bags.add', 'Add to Published Book Bags');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:circ.view', 'View Circulations');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:circ.renew', 'Renew Circulations');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:circ.checkout', 'Checkout Items');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:hold.view', 'View Holds');
INSERT INTO container.user_bucket_type (code,label) VALUES ('folks:hold.cancel', 'Cancel Holds');



CREATE SCHEMA action_trigger;

CREATE TABLE action_trigger.hook (
    key         TEXT    PRIMARY KEY,
    core_type   TEXT    NOT NULL,
    description TEXT,
    passive     BOOL    NOT NULL DEFAULT FALSE
);
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkout','circ','Item checked out to user');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkin','circ','Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('lost','circ','Circulating Item marked Lost');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('lost.found','circ','Lost Circulating Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('lost.auto','circ','Circulating Item automatically marked lost');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('claims_returned','circ','Circulating Item marked Claims Returned');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('claims_returned.found','circ','Claims Returned Circulating Item is checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('missing','acp','Item marked Missing');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('missing.found','acp','Missing Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('transit.start','acp','An Item is placed into transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('transit.finish','acp','An Item is received from a transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_request.success','ahr','A hold is succefully placed');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_request.failure','ahr','A hold is attempted by not succefully placed');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.capture','ahr','A targeted Item is captured for a hold');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.available','ahr','A held item is ready for pickup');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_transit.start','ahtc','A hold-captured Item is placed into transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_transit.finish','ahtc','A hold-captured Item is received from a transit');
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('checkout.due','circ','Checked out Item is Due',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_FINES','ausp','Patron has exceeded allowed fines',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_OVERDUE_COUNT','ausp','Patron has exceeded allowed overdue count',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_CHECKOUT_COUNT','ausp','Patron has exceeded allowed checkout count',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_COLLECTIONS_WARNING','ausp','Patron has exceeded maximum fine amount for collections department warning',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('format.po.jedi','acqpo','Formats a Purchase Order as a JEDI document',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('format.po.html','acqpo','Formats a Purchase Order as an HTML document',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('format.po.pdf','acqpo','Formats a Purchase Order as a PDF document',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('damaged','acp','Item marked damaged');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkout.damaged','circ','A circulating item is marked damaged and the patron is fined');
-- and much more, I'm sure

-- Specialized collection modules.  Given an FM object, gather some info and return a scalar or ref.
CREATE TABLE action_trigger.collector (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Collector:: namespace
    description TEXT
);
INSERT INTO action_trigger.collector (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
--INSERT INTO action_trigger.collector (module,description) VALUES ('CircCountsByCircMod','Count of Circulations for a User, broken down by circulation modifier');

-- Simple tests on an FM object from hook.core_type to test for "should we still do this."
CREATE TABLE action_trigger.validator (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Validator:: namespace
    description TEXT
);
INSERT INTO action_trigger.validator (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
INSERT INTO action_trigger.validator (module,description) VALUES ('NOOP_True','Always returns true -- validation always passes');
INSERT INTO action_trigger.validator (module,description) VALUES ('NOOP_False','Always returns false -- validation always fails');
INSERT INTO action_trigger.validator (module,description) VALUES ('CircIsOpen','Check that the circulation is still open');
INSERT INTO action_trigger.validator (module,description) VALUES ('HoldIsAvailable','Check that an item is on the hold shelf');
INSERT INTO action_trigger.validator (module,description) VALUES ('CircIsOverdue','Check that the circulation is overdue');

-- After an event passes validation (action_trigger.validator), the reactor processes it.
CREATE TABLE action_trigger.reactor (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Reactor:: namespace
    description TEXT
);
INSERT INTO action_trigger.reactor (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
INSERT INTO action_trigger.reactor (module,description) VALUES ('NOOP_True','Always returns true -- reaction always passes');
INSERT INTO action_trigger.reactor (module,description) VALUES ('NOOP_False','Always returns false -- reaction always fails');
INSERT INTO action_trigger.reactor (module,description) VALUES ('SendEmail','Send an email based on a user-defined template');
INSERT INTO action_trigger.reactor (module,description) VALUES ('GenerateBatchOverduePDF','Output a batch PDF of overdue notices for printing');
INSERT INTO action_trigger.reactor (module,description) VALUES ('MarkItemLost','Marks a circulation and associated item as lost');
INSERT INTO action_trigger.reactor (module,description) VALUES ('ApplyCircFee','Applies a billing with a pre-defined amount to a circulation');
INSERT INTO action_trigger.reactor (module,description) VALUES ('ProcessTemplate', 'Processes the configured template');

-- After an event is reacted to (either succes or failure) a cleanup module is run against the resulting environment
CREATE TABLE action_trigger.cleanup (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Cleanup:: namespace
    description TEXT
);
INSERT INTO action_trigger.cleanup (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
INSERT INTO action_trigger.cleanup (module,description) VALUES ('NOOP_True','Always returns true -- cleanup always passes');
INSERT INTO action_trigger.cleanup (module,description) VALUES ('NOOP_False','Always returns false -- cleanup always fails');
INSERT INTO action_trigger.cleanup (module,description) VALUES ('ClearAllPending','Remove all future, pending notifications for this target');

CREATE TABLE action_trigger.event_definition (
    id              SERIAL      PRIMARY KEY,
    active          BOOL        NOT NULL DEFAULT TRUE,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    name            TEXT        NOT NULL,
    hook            TEXT        NOT NULL REFERENCES action_trigger.hook (key) DEFERRABLE INITIALLY DEFERRED,
    validator       TEXT        NOT NULL REFERENCES action_trigger.validator (module) DEFERRABLE INITIALLY DEFERRED,
    reactor         TEXT        NOT NULL REFERENCES action_trigger.reactor (module) DEFERRABLE INITIALLY DEFERRED,
    cleanup_success TEXT        REFERENCES action_trigger.cleanup (module) DEFERRABLE INITIALLY DEFERRED,
    cleanup_failure TEXT        REFERENCES action_trigger.cleanup (module) DEFERRABLE INITIALLY DEFERRED,
    delay           INTERVAL    NOT NULL DEFAULT '5 minutes',
    delay_field     TEXT,                 -- for instance, xact_start on a circ hook ... look for fields on hook.core_type where datatype=timestamp? If not set, delay from now()
    group_field     TEXT,                 -- field from this.hook.core_type to batch event targets together on, fed into reactor a group at a time.
    template        TEXT,                 -- the TT block.  will have an 'environment' hash (or array of hashes, grouped events) built up by validator and collector(s), which can be modified.
    CONSTRAINT ev_def_owner_hook_val_react_clean_delay_once UNIQUE (owner, hook, validator, reactor, delay, delay_field),
    CONSTRAINT ev_def_name_owner_once UNIQUE (owner, name)
);

CREATE TABLE action_trigger.environment (
    id          SERIAL  PRIMARY KEY,
    event_def   INT     NOT NULL REFERENCES action_trigger.event_definition (id) DEFERRABLE INITIALLY DEFERRED,
    path        TEXT,       -- fields to flesh. given a hook with a core_type of circ, imagine circ_lib.parent_ou expanding to
                            -- {flesh: 2, flesh_fields: {circ: ['circ_lib'], aou: ['parent_ou']}} ... default is to flesh all
                            -- at flesh depth 1
    collector   TEXT    REFERENCES action_trigger.collector (module) DEFERRABLE INITIALLY DEFERRED, -- if set, given the object at 'path', return some data
                                                                      -- to be stashed at environment.<label>
    label       TEXT    CHECK (label NOT IN ('result','target','event')),
    CONSTRAINT env_event_label_once UNIQUE (event_def,label)
);

CREATE TABLE action_trigger.event_output (
    id              BIGSERIAL   PRIMARY KEY,
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_error        BOOLEAN     NOT NULL DEFAULT FALSE,
    data            TEXT        NOT NULL
);

CREATE TABLE action_trigger.event (
    id              BIGSERIAL   PRIMARY KEY,
    target          BIGINT      NOT NULL, -- points at the id from class defined by event_def.hook.core_type
    event_def       INT         REFERENCES action_trigger.event_definition (id) DEFERRABLE INITIALLY DEFERRED,
    add_time        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_time        TIMESTAMPTZ NOT NULL,
    start_time      TIMESTAMPTZ,
    update_time     TIMESTAMPTZ,
    complete_time   TIMESTAMPTZ,
    update_process  INT,
    state           TEXT        NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','invalid','found','collecting','collected','validating','valid','reacting','reacted','cleaning','complete','error')),
    template_output BIGINT      REFERENCES action_trigger.event_output (id),
    error_output    BIGINT      REFERENCES action_trigger.event_output (id)
);

CREATE TABLE action_trigger.event_params (
    id          BIGSERIAL   PRIMARY KEY,
    event_def   INT         NOT NULL REFERENCES action_trigger.event_definition (id) DEFERRABLE INITIALLY DEFERRED,
    param       TEXT        NOT NULL, -- the key under environment.event.params to store the output of ...
    value       TEXT        NOT NULL, -- ... the eval() output of this.  Has access to environment (and, well, all of perl)
    CONSTRAINT event_params_event_def_param_once UNIQUE (event_def,param)
);



-- Trigger Event Definitions -------------------------------------------------

-- Sample Overdue Notice --

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field, group_field, template) 
    VALUES (1, 'f', 1, '7 Day Overdue Email Notification', 'checkout.due', 'CircIsOverdue', 'SendEmail', '7 days', 'due_date', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Overdue Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following items are overdue.

[% FOR circ IN target %]
    Title: [% circ.target_copy.call_number.record.simple_record.title %] 
    Barcode: [% circ.target_copy.barcode %] 
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Item Cost: [% helpers.get_copy_price(circ.target_copy) %]
    Total Owed For Transaction: [% circ.billable_transaction.summary.total_owed %]
    Library: [% circ.circ_lib.name %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (1, 'target_copy.call_number.record.simple_record'),
    (1, 'usr'),
    (1, 'billable_transaction.summary'),
    (1, 'circ_lib.billing_address');
  

-- Sample Mark Long-Overdue Item Lost --

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field) 
    VALUES (2, 'f', 1, '90 Day Overdue Mark Lost', 'checkout.due', 'CircIsOverdue', 'MarkItemLost', '90 days', 'due_date');

-- Sample Auto Mark Lost Notice --

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, template) 
    VALUES (3, 'f', 1, '90 Day Overdue Mark Lost Notice', 'lost.auto', 'NOOP_True', 'SendEmail', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Overdue Items Marked Lost

Dear [% user.family_name %], [% user.first_given_name %]
The following items are 90 days overdue and have been marked LOST.

[% FOR circ IN target %]
    Title: [% circ.target_copy.call_number.record.simple_record.title %] 
    Barcode: [% circ.target_copy.barcode %] 
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Item Cost: [% helpers.get_copy_price(circ.target_copy) %]
    Total Owed For Transaction: [% circ.billable_transaction.summary.total_owed %]
    Library: [% circ.circ_lib.name %]
[% END %]

$$);


INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (3, 'target_copy.call_number.record.simple_record'),
    (3, 'usr'),
    (3, 'billable_transaction.summary'),
    (3, 'circ_lib.billing_address');

-- Sample Purchase Order HTML Template --

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, template) 
    VALUES (4, 't', 1, 'PO HTML', 'format.po.html', 'NOOP_True', 'ProcessTemplate', 
$$
[%- USE date -%]
[%-
    # find a lineitem attribute by name and optional type
    BLOCK get_li_attr;
        FOR attr IN li.attributes;
            IF attr.attr_name == attr_name;
                IF !attr_type OR attr_type == attr.attr_type;
                    attr.attr_value;
                    LAST;
                END;
            END;
        END;
    END
-%]

<h2>Purchase Order [% target.id %]</h2>
<br/>
date <b>[% date.format(date.now, '%Y%m%d') %]</b>
<br/>

<style>
    table td { padding:5px; border:1px solid #aaa;}
    table { width:95%; border-collapse:collapse; }
</style>
<table id='vendor-table'>
  <tr>
    <td valign='top'>Vendor</td>
    <td>
      <div>[% target.provider.name %]</div>
      <div>[% target.provider.addresses.0.street1 %]</div>
      <div>[% target.provider.addresses.0.street2 %]</div>
      <div>[% target.provider.addresses.0.city %]</div>
      <div>[% target.provider.addresses.0.state %]</div>
      <div>[% target.provider.addresses.0.country %]</div>
      <div>[% target.provider.addresses.0.post_code %]</div>
    </td>
    <td valign='top'>Ship to / Bill to</td>
    <td>
      <div>[% target.ordering_agency.name %]</div>
      <div>[% target.ordering_agency.billing_address.street1 %]</div>
      <div>[% target.ordering_agency.billing_address.street2 %]</div>
      <div>[% target.ordering_agency.billing_address.city %]</div>
      <div>[% target.ordering_agency.billing_address.state %]</div>
      <div>[% target.ordering_agency.billing_address.country %]</div>
      <div>[% target.ordering_agency.billing_address.post_code %]</div>
    </td>
  </tr>
</table>

<br/><br/><br/>

<table>
  <thead>
    <tr>
      <th>PO#</th>
      <th>ISBN or Item #</th>
      <th>Title</th>
      <th>Quantity</th>
      <th>Unit Price</th>
      <th>Line Total</th>
    </tr>
  </thead>
  <tbody>

  [% subtotal = 0 %]
  [% FOR li IN target.lineitems %]

  <tr>
    [% count = li.lineitem_details.size %]
    [% price = PROCESS get_li_attr attr_name = 'estimated_price' %]
    [% litotal = (price * count) %]
    [% subtotal = subtotal + litotal %]
    [% isbn = PROCESS get_li_attr attr_name = 'isbn' %]
    [% ident = PROCESS get_li_attr attr_name = 'identifier' %]

    <td>[% target.id %]</td>
    <td>[% isbn || ident %]</td>
    <td>[% PROCESS get_li_attr attr_name = 'title' %]</td>
    <td>[% count %]</td>
    <td>[% price %]</td>
    <td>[% litotal %]</td>
  </tr>
  [% END %]
  <tr>
    <td/><td/><td/><td/>
    <td>Sub Total</td>
    <td>[% subtotal %]</td>
  </tr>
  </tbody>
</table>

<br/>

Total Line Item Count: [% target.lineitems.size %]
$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (4, 'lineitems.lineitem_details.fund'),
    (4, 'lineitems.lineitem_details.location'),
    (4, 'lineitems.lineitem_details.owning_lib'),
    (4, 'ordering_agency.mailing_address'),
    (4, 'ordering_agency.billing_address'),
    (4, 'provider.addresses'),
    (4, 'lineitems.attributes');

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field, group_field, template)
    VALUES (5, 'f', 1, 'Hold Ready for Pickup Email Notification', 'hold.available', 'HoldIsAvailable', 'SendEmail', '30 minutes', 'capture_time', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Hold Available Notification

Dear [% user.family_name %], [% user.first_given_name %]
The item(s) you requested are available for pickup from the Library.

[% FOR hold IN target %]
    Title: [% hold.current_copy.call_number.record.simple_record.title %]
    Author: [% hold.current_copy.call_number.record.simple_record.author %]
    Call Number: [% hold.current_copy.call_number.label %]
    Barcode: [% hold.current_copy.barcode %]
    Library: [% hold.pickup_lib.name %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (5, 'current_copy.call_number.record.simple_record'),
    (5, 'usr'),
    (5, 'pickup_lib.billing_address');


SELECT SETVAL('action_trigger.event_definition_id_seq'::TEXT, 100);


CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN

        SELECT  COUNT(*) INTO counter
          FROM  xpath_table(
                    'id',
                    'marc',
                    'acq.lineitem',
                    '//*[@tag="856"]',
                    'id=' || lineitem
                ) as t(i int,c text);

        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim" tag="856">' ||
                        array_to_string(
                            array_accum(
                                '<subfield code="' || subfield || '">' ||
                                regexp_replace(
                                    regexp_replace(
                                        regexp_replace(data,'&','&amp;','g'),
                                        '>', '&gt;', 'g'
                                    ),
                                    '<', '&lt;', 'g'
                                ) || '</subfield>'
                            ), ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,subfield text,data text);

            uri_text := uri_text || uri_datafield;
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

    -- Find and move metarecords to the target record
    SELECT  INTO metarec *
      FROM  metabib.metarecord
      WHERE master_record = source_record;

    IF FOUND THEN
        UPDATE  metabib.metarecord
          SET   master_record = target_record,
            mods = NULL
          WHERE id = metarec.id;

        moved_objects := moved_objects + 1;
    END IF;

    -- Find call numbers attached to the source ...
    FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

        SELECT  INTO target_cn *
          FROM  asset.call_number
          WHERE label = source_cn.label
            AND owning_lib = source_cn.owning_lib
            AND record = target_record;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copies to that, and ...
            UPDATE  asset.copy
              SET   call_number = target_cn.id
              WHERE call_number = source_cn.id;

            -- ... move V holds to the move-target call number
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP

                UPDATE  action.hold_request
                  SET   target = target_cn.id
                  WHERE id = hold.id;

                moved_objects := moved_objects + 1;
            END LOOP;

        -- ... if not ...
        ELSE
            -- ... just move the call number to the target record
            UPDATE  asset.call_number
              SET   record = target_record
              WHERE id = source_cn.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find T holds targeting the source record ...
    FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

        -- ... and move them to the target record
        UPDATE  action.hold_request
          SET   target = target_record
          WHERE id = hold.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial records targeting the source record ...
    FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE  serial.record_entry
          SET   record = target_record
          WHERE id = ser_rec.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

    -- That's all, folks!
    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION actor.usr_merge_rows( table_name TEXT, col_name TEXT, src_usr INT, dest_usr INT ) RETURNS VOID AS $$
DECLARE
    sel TEXT;
    upd TEXT;
    del TEXT;
    cur_row RECORD;
BEGIN
    sel := 'SELECT id::BIGINT FROM ' || table_name || ' WHERE ' || quote_ident(col_name) || ' = ' || quote_literal(src_usr);
    upd := 'UPDATE ' || table_name || ' SET ' || quote_ident(col_name) || ' = ' || quote_literal(dest_usr) || ' WHERE id = ';
    del := 'DELETE FROM ' || table_name || ' WHERE id = ';
    FOR cur_row IN EXECUTE sel LOOP
        BEGIN
            --RAISE NOTICE 'Attempting to merge % %', table_name, cur_row.id;
            EXECUTE upd || cur_row.id;
        EXCEPTION WHEN unique_violation THEN
            --RAISE NOTICE 'Deleting conflicting % %', table_name, cur_row.id;
            EXECUTE del || cur_row.id;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_merge_rows(TEXT, TEXT, INT, INT) IS $$
/**
 * Attempts to move each row of the specified table from src_user to dest_user.  
 * Where conflicts exist, the conflicting "source" row is deleted.
 */
$$;


CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
BEGIN

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
    PERFORM actor.usr_merge_rows('container.biblio_record_entry_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.call_number_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.copy_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.user_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.user_bucket_item', 'target_user', src_usr, dest_usr);

    -- vandelay.*
    PERFORM actor.usr_merge_rows('vandelay.queue', 'owner', src_usr, dest_usr);

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
    PERFORM actor.usr_merge_rows('acq.picklist', 'owner', src_usr, dest_usr);
    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.template', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.report', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.schedule', 'runner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.template_folder', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.report_folder', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.output_folder', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_merge(INT, INT, BOOLEAN, BOOLEAN, BOOLEAN) IS $$
/**
 * Merges all user date from src_usr to dest_usr.  When collisions occur, 
 * keep dest_usr's data and delete src_usr's data.
 */
$$;



CREATE OR REPLACE FUNCTION actor.approve_pending_address(pending_id INT) RETURNS BIGINT AS $$
DECLARE
    old_id INT;
BEGIN
    SELECT INTO old_id replaces FROM actor.usr_address where id = pending_id;
    IF old_id IS NULL THEN
        UPDATE actor.usr_address SET pending = 'f' WHERE id = pending_id;
        RETURN pending_id;
    END IF;
    -- address replaces an existing address
    DELETE FROM actor.usr_address WHERE id = -old_id;
    UPDATE actor.usr_address SET id = -id WHERE id = old_id;
    UPDATE actor.usr_address SET replaces = NULL, id = old_id, pending = 'f' WHERE id = pending_id;
    RETURN old_id;
END
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.approve_pending_address(INT) IS $$
/**
 * Replaces an address with a pending address.  This is done by giving the pending 
 * address the ID of the old address.  The replaced address is retained with -id.
 */
$$;

COMMIT;

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
 SELECT cp.id, COALESCE(sum(c.circ_count), 0::bigint) + COALESCE(count(circ.id), 0::bigint) + COALESCE(count(acirc.id), 0::bigint) AS circ_count
   FROM asset."copy" cp
   LEFT JOIN extend_reporter.legacy_circ_count c USING (id)
   LEFT JOIN "action".circulation circ ON circ.target_copy = cp.id
   LEFT JOIN "action".aged_circulation acirc ON acirc.target_copy = cp.id
  GROUP BY cp.id;

SELECT reporter.disable_materialized_simple_record_trigger();

CREATE OR REPLACE FUNCTION reporter.simple_rec_update (r_id BIGINT, deleted BOOL) RETURNS BOOL AS $$
BEGIN

    DELETE FROM reporter.materialized_simple_record WHERE id = r_id;

    IF NOT deleted THEN
        INSERT INTO reporter.materialized_simple_record SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record WHERE id = r_id;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_update (r_id BIGINT) RETURNS BOOL AS $$
    SELECT reporter.simple_rec_update($1, FALSE);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_delete (r_id BIGINT) RETURNS BOOL AS $$
    SELECT reporter.simple_rec_update($1, TRUE);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_sync () RETURNS TRIGGER AS $$
DECLARE
    r_id        BIGINT;
    deleted     BOOL;
BEGIN
    IF TG_OP IN ('DELETE') THEN
        r_id := OLD.record;
        deleted := TRUE;
    ELSE
        r_id := NEW.record;
        deleted := FALSE;
    END IF;

    PERFORM reporter.simple_rec_update(r_id, deleted);

    IF deleted THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_bib_sync () RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted THEN
        DELETE FROM reporter.materialized_simple_record WHERE id = NEW.id;
        RETURN NEW;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER zzz_update_materialized_simple_rec_delete_tgr
    AFTER UPDATE ON biblio.record_entry
    FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_bib_sync();



---------!!!!!!!!!!!!!!!!!!!!!!---------------
--  Must go after COMMIT!!
---------!!!!!!!!!!!!!!!!!!!!!!---------------

INSERT INTO config.z3950_source (name, label, host, port, db, auth)
	VALUES ('biblios', oils_i18n_gettext('biblios','biblios.net', 'czs', 'label'), 'z3950.biblios.net', 210, 'bibliographic', FALSE);
 

INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (19, 'biblios','tcn', oils_i18n_gettext(19, 'Title Control Number', 'cza', 'label'), 12, 1);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (20, 'biblios', 'isbn', oils_i18n_gettext(20, 'ISBN', 'cza', 'label'), 7, 6);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (21, 'biblios', 'lccn', oils_i18n_gettext(21, 'LCCN', 'cza', 'label'), 9, 1);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (22, 'biblios', 'author', oils_i18n_gettext(22, 'Author', 'cza', 'label'), 1003, 6);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (23, 'biblios', 'title', oils_i18n_gettext(23, 'Title', 'cza', 'label'), 4, 6);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (24, 'biblios', 'issn', oils_i18n_gettext(24, 'ISSN', 'cza', 'label'), 8, 1);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (25, 'biblios', 'publisher', oils_i18n_gettext(25, 'Publisher', 'cza', 'label'), 1018, 6);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (26, 'biblios', 'pubdate', oils_i18n_gettext(26, 'Publication Date', 'cza', 'label'), 31, 1);
INSERT INTO config.z3950_attr (id, source, name, label, code, format)
	VALUES (27, 'biblios', 'item_type', oils_i18n_gettext(27, 'Item Type', 'cza', 'label'), 1001, 1);

INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_FUNDING_SOURCE', 'Allow a user to delete a funding source');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_FUNDING_SOURCE', 'Allow a user to view a funding source');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_FUNDING_SOURCE', 'Allow a user to update a funding source');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_FUND', 'Allow a user to create a new fund');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_FUND', 'Allow a user to delete a fund');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_FUND', 'Allow a user to view a fund');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_FUND', 'Allow a user to update a fund');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_FUND_ALLOCATION', 'Allow a user to create a new fund allocation');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_FUND_ALLOCATION', 'Allow a user to delete a fund allocation');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_FUND_ALLOCATION', 'Allow a user to view a fund allocation');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_FUND_ALLOCATION', 'Allow a user to update a fund allocation');
INSERT INTO permission.perm_list (code, description) VALUES ('GENERAL_ACQ', 'Lowest level permission required to access the ACQ interface');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_PROVIDER', 'Allow a user to create a new provider');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_PROVIDER', 'Allow a user to delate a provider');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_PROVIDER', 'Allow a user to view a provider');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_PROVIDER', 'Allow a user to update a provider');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_FUNDING_SOURCE', 'Allow a user to create/view/update/delete a funding source');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_ACQ_FUND', 'Allow a user to create/view/update/delete a fund');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_FUND', 'Allow a user to create/view/update/delete a fund');
INSERT INTO permission.perm_list (code, description) VALUES ('MANAGE_FUNDING_SOURCE', 'Allow a user to view/credit/debit a funding source');
INSERT INTO permission.perm_list (code, description) VALUES ('MANAGE_FUND', 'Allow a user to view/credit/debit a fund');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_PICKLIST', 'Allows a user to create a picklist');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_PROVIDER', 'Allow a user to create/view/update/delete a provider');
INSERT INTO permission.perm_list (code, description) VALUES ('MANAGE_PROVIDER', 'Allow a user to view and purchase from a provider');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_PICKLIST', 'Allow a user to view another users picklist');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_RECORD', 'Allow a staff member to directly remove a bibliographic record');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_CURRENCY_TYPE', 'Allow a user to create/view/update/delete a currency_type');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_BAD_DEBT', 'Allow a user to mark a transaction as bad (unrecoverable) debt');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_BILLING_TYPE', 'Allow a user to view billing types');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_AVAILABLE', 'Allow a user to mark an item status as ''available''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_CHECKED_OUT', 'Allow a user to mark an item status as ''checked out''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_BINDERY', 'Allow a user to mark an item status as ''bindery''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_LOST', 'Allow a user to mark an item status as ''lost''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_MISSING', 'Allow a user to mark an item status as ''missing''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_IN_PROCESS', 'Allow a user to mark an item status as ''in process''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_IN_TRANSIT', 'Allow a user to mark an item status as ''in transit''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_RESHELVING', 'Allow a user to mark an item status as ''reshelving''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_ON_HOLDS_SHELF', 'Allow a user to mark an item status as ''on holds shelf''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_ON_ORDER', 'Allow a user to mark an item status as ''on order''');
INSERT INTO permission.perm_list (code, description) VALUES ('MARK_ITEM_ILL', 'Allow a user to mark an item status as ''inter-library loan''');
INSERT INTO permission.perm_list (code, description) VALUES ('group_application.user.staff.acq', 'Allows a user to add/remove/edit users in the "ACQ" group');
INSERT INTO permission.perm_list (code, description) VALUES ('group_application.user.staff.acq_admin', 'Allows a user to add/remove/edit users in the "Acquisitions Administrator" group');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_PURCHASE_ORDER', 'Allows a user to create a purchase order');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_PURCHASE_ORDER', 'Allows a user to view a purchase order');
INSERT INTO permission.perm_list (code, description) VALUES ('IMPORT_ACQ_LINEITEM_BIB_RECORD', 'Allows a user to import a bib record from the acq staging area (on-order record) into the ILS bib data set');
INSERT INTO permission.perm_list (code, description) VALUES ('RECEIVE_PURCHASE_ORDER', 'Allows a user to mark a purchase order, lineitem, or individual copy as received');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_ORG_SETTINGS','Allows a user to view all org settings at the specified level');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_MFHD_RECORD', 'Allows a user to create a new MFHD record');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_MFHD_RECORD', 'Allows a user to update an MFHD record');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_MFHD_RECORD', 'Allows a user to delete an MFHD record');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_FUNDING_SOURCE', 'Allow a user to create a new funding source');

INSERT INTO permission.perm_list (code) VALUES ('CREATE_ACQ_FUNDING_SOURCE');
INSERT INTO permission.perm_list (code) VALUES ('DELETE_ACQ_FUNDING_SOURCE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ACQ_FUNDING_SOURCE');
INSERT INTO permission.perm_list (code) VALUES ('VIEW_ACQ_FUNDING_SOURCE');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.global.password_regex');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.global.juvenile_age_threshold');
INSERT INTO permission.perm_list (code) VALUES ('UPDATE_ORG_UNIT_SETTING.patron.password.use_phone');

INSERT INTO permission.grp_tree (name, parent, description, perm_interval, usergroup, application_perm) VALUES ('Acquisitions', 3, NULL, '3 years', TRUE, 'group_application.user.staff.acq');
INSERT INTO permission.grp_tree (name, parent, description, perm_interval, usergroup, application_perm) VALUES ('Acquisitions Administrators', (SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), NULL, '3 years', TRUE, 'group_application.user.staff.acq_admin');

-- You can't log into the staff client without this
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES (3, (SELECT id FROM permission.perm_list WHERE code = 'VIEW_ORG_SETTINGS'), 1, false);
-- MFHD permissions are necessary for serials work; add to the default catalogers group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES (5, (SELECT id FROM permission.perm_list WHERE code = 'CREATE_MFHD_RECORD'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES (5, (SELECT id FROM permission.perm_list WHERE code = 'DELETE_MFHD_RECORD'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES (5, (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_MFHD_RECORD'), 1, false);

-- Add basic acquisitions permissions to the Acquisitions group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'GENERAL_ACQ'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'VIEW_PICKLIST'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'CREATE_PICKLIST'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'CREATE_PURCHASE_ORDER'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'VIEW_PURCHASE_ORDER'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'RECEIVE_PURCHASE_ORDER'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'VIEW_PROVIDER'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_COPY'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions'), (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_VOLUME'), 1, false);

-- Add acquisitions administration permissions to the Acquisitions group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions Administrators'), (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_PROVIDER'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions Administrators'), (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_FUNDING_SOURCE'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions Administrators'), (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_ACQ_FUND'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions Administrators'), (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_FUND'), 1, false);
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES ((SELECT id FROM permission.grp_tree WHERE name = 'Acquisitions Administrators'), (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_CURRENCY_TYPE'), 1, false);

SELECT SETVAL('permission.perm_list_id_seq'::TEXT, (SELECT MAX(id) FROM permission.perm_list));

ALTER TABLE auditor.action_hold_request_history ADD COLUMN cancel_cause INT;
ALTER TABLE auditor.action_hold_request_history ADD COLUMN cancel_note TEXT;

CREATE OR REPLACE FUNCTION tmp_populate_p_b_bt () RETURNS BOOL AS $$
DECLARE
    p   RECORD;
BEGIN
    FOR p IN
        SELECT  DISTINCT xact
          FROM  money.payment
          WHERE NOT voided
                AND amount > 0.0
    LOOP

        INSERT INTO money.materialized_payment_by_billing_type (
            xact, payment, billing, payment_ts, billing_ts,
            payment_type, billing_type, amount, billing_ou, payment_ou
        ) SELECT    xact, payment, billing, payment_ts, billing_ts,
                    payment_type, billing_type, amount, billing_ou, payment_ou
          FROM money.payment_by_billing_type( p.xact );

    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

SELECT tmp_populate_p_b_bt();

DROP FUNCTION tmp_populate_p_b_bt ();


UPDATE config.xml_transform SET xslt=$$<xsl:stylesheet xmlns="http://www.loc.gov/mods/v3" xmlns:marc="http://www.loc.gov/MARC21/slim"
	xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
	exclude-result-prefixes="xlink marc" version="1.0">
	<xsl:output encoding="UTF-8" indent="yes" method="xml"/>

	<xsl:variable name="ascii">
		<xsl:text> !"#$%&amp;'()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~</xsl:text>
	</xsl:variable>

	<xsl:variable name="latin1">
		<xsl:text> ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ</xsl:text>
	</xsl:variable>
	<!-- Characters that usually don't need to be escaped -->
	<xsl:variable name="safe">
		<xsl:text>!'()*-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~</xsl:text>
	</xsl:variable>

	<xsl:variable name="hex">0123456789ABCDEF</xsl:variable>


	
	<!--MARC21slim2MODS3-3.xsl
Revision 1.27 - Mapped 648 to <subject> 2009/03/13 tmee
Revision 1.26 - Added subfield $s mapping for 130/240/730  2008/10/16 tmee
Revision 1.25 - Mapped 040e to <descriptiveStandard> and Leader/18 to <descriptive standard>aacr2  2008/09/18 tmee
Revision 1.24 - Mapped 852 subfields $h, $i, $j, $k, $l, $m, $t to <shelfLocation> and 852 subfield $u to <physicalLocation> with @xlink 2008/09/17 tmee
Revision 1.23 - Commented out xlink/uri for subfield 0 for 130/240/730, 100/700, 110/710, 111/711 as these are currently unactionable  2008/09/17  tmee
Revision 1.22 - Mapped 022 subfield $l to type "issn-l" subfield $m to output identifier element with corresponding @type and @invalid eq 'yes'2008/09/17  tmee
Revision 1.21 - Mapped 856 ind2=1 or ind2=2 to <relatedItem><location><url>  2008/07/03  tmee
Revision 1.20 - Added genre w/@auth="contents of 2" and type= "musical composition"  2008/07/01  tmee
Revision 1.19 - Added genre offprint for 008/24+ BK code 2  2008/07/01  tmee
Revision 1.18 - Added xlink/uri for subfield 0 for 130/240/730, 100/700, 110/710, 111/711  2008/06/26  tmee
Revision 1.17 - Added mapping of 662 2008/05/14 tmee	
Revision 1.16 - Changed @authority from "marc" to "marcgt" for 007 and 008 codes mapped to a term in <genre> 2007/07/10  tmee
Revision 1.15 - For field 630, moved call to part template outside title element  2007/07/10  tmee
Revision 1.14 - Fixed template isValid and fields 010, 020, 022, 024, 028, and 037 to output additional identifier elements with corresponding @type and @invalid eq 'yes' when subfields z or y (in the case of 022) exist in the MARCXML ::: 2007/01/04 17:35:20 cred
Revision 1.13 - Changed order of output under cartographics to reflect schema  2006/11/28  tmee
Revision 1.12 - Updated to reflect MODS 3.2 Mapping  2006/10/11  tmee
Revision 1.11 - The attribute objectPart moved from <languageTerm> to <language>  2006/04/08  jrad
Revision 1.10 - MODS 3.1 revisions to language and classification elements  (plus ability to find marc:collection embedded in wrapper elements such as SRU zs: wrappers)  2006/02/06  ggar
Revision 1.9 - Subfield $y was added to field 242 2004/09/02 10:57 jrad
Revision 1.8 - Subject chopPunctuation expanded and attribute fixes 2004/08/12 jrad
Revision 1.7 - 2004/03/25 08:29 jrad
Revision 1.6 - Various validation fixes 2004/02/20 ntra
Revision 1.5 - MODS2 to MODS3 updates, language unstacking and de-duping, chopPunctuation expanded  2003/10/02 16:18:58  ntra
Revision 1.3 - Additional Changes not related to MODS Version 2.0 by ntra
Revision 1.2 - Added Log Comment  2003/03/24 19:37:42  ckeith
-->
	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="//marc:collection">
				<modsCollection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
					xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:collection/marc:record">
						<mods version="3.3">
							<xsl:call-template name="marcRecord"/>
						</mods>
					</xsl:for-each>
				</modsCollection>
			</xsl:when>
			<xsl:otherwise>
				<mods xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="3.3"
					xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:record">
						<xsl:call-template name="marcRecord"/>
					</xsl:for-each>
				</mods>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="marcRecord">
		<xsl:variable name="leader" select="marc:leader"/>
		<xsl:variable name="leader6" select="substring($leader,7,1)"/>
		<xsl:variable name="leader7" select="substring($leader,8,1)"/>
		<xsl:variable name="controlField008" select="marc:controlfield[@tag='008']"/>
		<xsl:variable name="typeOf008">
			<xsl:choose>
				<xsl:when test="$leader6='a'">
					<xsl:choose>
						<xsl:when
							test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'">BK</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'">SE</xsl:when>
					</xsl:choose>
				</xsl:when>
				<xsl:when test="$leader6='t'">BK</xsl:when>
				<xsl:when test="$leader6='p'">MM</xsl:when>
				<xsl:when test="$leader6='m'">CF</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">MP</xsl:when>
				<xsl:when test="$leader6='g' or $leader6='k' or $leader6='o' or $leader6='r'">VM</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d' or $leader6='i' or $leader6='j'"
				>MU</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:for-each select="marc:datafield[@tag='245']">
			<titleInfo>
				<xsl:variable name="title">
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='b']">
							<xsl:call-template name="specialSubfieldSelect">
								<xsl:with-param name="axis">b</xsl:with-param>
								<xsl:with-param name="beforeCodes">afgk</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">abfgk</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="$title"/>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<xsl:choose>
					<xsl:when test="@ind2&gt;0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind2)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind2+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop"/>
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:if test="marc:subfield[@code='b']">
					<subTitle>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="axis">b</xsl:with-param>
									<xsl:with-param name="anyCodes">b</xsl:with-param>
									<xsl:with-param name="afterCodes">afgk</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</subTitle>
				</xsl:if>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='210']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='242']">
			<titleInfo type="translated">
				<!--09/01/04 Added subfield $y-->
				<xsl:for-each select="marc:subfield[@code='y']">
					<xsl:attribute name="lang">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='i']">
					<xsl:attribute name="displayLabel">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, b -->
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<!-- 1/04 fix -->
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='246']">
			<titleInfo type="alternative">
				<xsl:for-each select="marc:subfield[@code='i']">
					<xsl:attribute name="displayLabel">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, $b -->
								<xsl:with-param name="codes">af</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each
			select="marc:datafield[@tag='130']|marc:datafield[@tag='240']|marc:datafield[@tag='730'][@ind2!='2']">
			<titleInfo type="uniform">
				<title>
					<!-- deleted uri for subfield 0
						<xsl:call-template name="uri"/>
					-->

					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if
								test="(contains('adfklmors',@code) and (not(../marc:subfield[@code='n' or @code='p']) or (following-sibling::marc:subfield[@code='n' or @code='p'])))">
								<xsl:value-of select="text()"/>
								<xsl:text> </xsl:text>
							</xsl:if>
						</xsl:for-each>
					</xsl:variable>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='740'][@ind2!='2']">
			<titleInfo type="alternative">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ah</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='100']">
			<name type="personal">

				<!-- deleted uri for subfield 0
				<xsl:call-template name="uri"/>
				-->

				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='110']">
			<name type="corporate">

				<!-- deleted uri for subfield 0
					<xsl:call-template name="uri"/>
				-->

				<xsl:call-template name="nameABCDN"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='111']">
			<name type="conference">

				<!-- deleted uri for subfield 0
					<xsl:call-template name="uri"/>
				-->

				<xsl:call-template name="nameACDEQ"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='700'][not(marc:subfield[@code='t'])]">
			<name type="personal">

				<!-- deleted uri for subfield 0
					<xsl:call-template name="uri"/>
				-->

				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='710'][not(marc:subfield[@code='t'])]">
			<name type="corporate">

				<!-- deleted uri for subfield 0
					<xsl:call-template name="uri"/>
				-->

				<xsl:call-template name="nameABCDN"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='711'][not(marc:subfield[@code='t'])]">
			<name type="conference">

				<!-- deleted uri for subfield 0
					<xsl:call-template name="uri"/>
				-->

				<xsl:call-template name="nameACDEQ"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='720'][not(marc:subfield[@code='t'])]">
			<name>
				<xsl:if test="@ind1=1">
					<xsl:attribute name="type">
						<xsl:text>personal</xsl:text>
					</xsl:attribute>
				</xsl:if>
				<namePart>
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</namePart>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<typeOfResource>
			<xsl:if test="$leader7='c'">
				<xsl:attribute name="collection">yes</xsl:attribute>
			</xsl:if>
			<xsl:if test="$leader6='d' or $leader6='f' or $leader6='p' or $leader6='t'">
				<xsl:attribute name="manuscript">yes</xsl:attribute>
			</xsl:if>
			<xsl:choose>
				<xsl:when test="$leader6='a' or $leader6='t'">text</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">cartographic</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d'">notated music</xsl:when>
				<xsl:when test="$leader6='i'">sound recording-nonmusical</xsl:when>
				<xsl:when test="$leader6='j'">sound recording-musical</xsl:when>
				<xsl:when test="$leader6='k'">still image</xsl:when>
				<xsl:when test="$leader6='g'">moving image</xsl:when>
				<xsl:when test="$leader6='r'">three dimensional object</xsl:when>
				<xsl:when test="$leader6='m'">software, multimedia</xsl:when>
				<xsl:when test="$leader6='p'">mixed material</xsl:when>
			</xsl:choose>
		</typeOfResource>
		<xsl:if test="substring($controlField008,26,1)='d'">
			<genre authority="marcgt">globe</genre>
		</xsl:if>
		<xsl:if
			test="marc:controlfield[@tag='007'][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
			<genre authority="marcgt">remote-sensing image</genre>
		</xsl:if>
		<xsl:if test="$typeOf008='MP'">
			<xsl:variable name="controlField008-25" select="substring($controlField008,26,1)"/>
			<xsl:choose>
				<xsl:when
					test="$controlField008-25='a' or $controlField008-25='b' or $controlField008-25='c' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
					<genre authority="marcgt">map</genre>
				</xsl:when>
				<xsl:when
					test="$controlField008-25='e' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
					<genre authority="marcgt">atlas</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='SE'">
			<xsl:variable name="controlField008-21" select="substring($controlField008,22,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-21='d'">
					<genre authority="marcgt">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='l'">
					<genre authority="marcgt">loose-leaf</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='m'">
					<genre authority="marcgt">series</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='n'">
					<genre authority="marcgt">newspaper</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='p'">
					<genre authority="marcgt">periodical</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='w'">
					<genre authority="marcgt">web site</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK' or $typeOf008='SE'">
			<xsl:variable name="controlField008-24" select="substring($controlField008,25,4)"/>
			<xsl:choose>
				<xsl:when test="contains($controlField008-24,'a')">
					<genre authority="marcgt">abstract or summary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'b')">
					<genre authority="marcgt">bibliography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'c')">
					<genre authority="marcgt">catalog</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'d')">
					<genre authority="marcgt">dictionary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'e')">
					<genre authority="marcgt">encyclopedia</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'f')">
					<genre authority="marcgt">handbook</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'g')">
					<genre authority="marcgt">legal article</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'i')">
					<genre authority="marcgt">index</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'k')">
					<genre authority="marcgt">discography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'l')">
					<genre authority="marcgt">legislation</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'m')">
					<genre authority="marcgt">theses</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'n')">
					<genre authority="marcgt">survey of literature</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'o')">
					<genre authority="marcgt">review</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'p')">
					<genre authority="marcgt">programmed text</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'q')">
					<genre authority="marcgt">filmography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'r')">
					<genre authority="marcgt">directory</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'s')">
					<genre authority="marcgt">statistics</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'t')">
					<genre authority="marcgt">technical report</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'v')">
					<genre authority="marcgt">legal case and case notes</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'w')">
					<genre authority="marcgt">law report or digest</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'z')">
					<genre authority="marcgt">treaty</genre>
				</xsl:when>
			</xsl:choose>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-29='1'">
					<genre authority="marcgt">conference publication</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='CF'">
			<xsl:variable name="controlField008-26" select="substring($controlField008,27,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-26='a'">
					<genre authority="marcgt">numeric data</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='e'">
					<genre authority="marcgt">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='f'">
					<genre authority="marcgt">font</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='g'">
					<genre authority="marcgt">game</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK'">
			<xsl:if test="substring($controlField008,25,1)='j'">
				<genre authority="marcgt">patent</genre>
			</xsl:if>
			<xsl:if test="substring($controlField008,25,1)='2'">
				<genre authority="marcgt">offprint</genre>
			</xsl:if>
			<xsl:if test="substring($controlField008,31,1)='1'">
				<genre authority="marcgt">festschrift</genre>
			</xsl:if>
			<xsl:variable name="controlField008-34" select="substring($controlField008,35,1)"/>
			<xsl:if
				test="$controlField008-34='a' or $controlField008-34='b' or $controlField008-34='c' or $controlField008-34='d'">
				<genre authority="marcgt">biography</genre>
			</xsl:if>
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-33='e'">
					<genre authority="marcgt">essay</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marcgt">drama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marcgt">comic strip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marcgt">fiction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='h'">
					<genre authority="marcgt">humor, satire</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marcgt">letter</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marcgt">novel</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='j'">
					<genre authority="marcgt">short story</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marcgt">speech</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='MU'">
			<xsl:variable name="controlField008-30-31" select="substring($controlField008,31,2)"/>
			<xsl:if test="contains($controlField008-30-31,'b')">
				<genre authority="marcgt">biography</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'c')">
				<genre authority="marcgt">conference publication</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'d')">
				<genre authority="marcgt">drama</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'e')">
				<genre authority="marcgt">essay</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'f')">
				<genre authority="marcgt">fiction</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'o')">
				<genre authority="marcgt">folktale</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'h')">
				<genre authority="marcgt">history</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'k')">
				<genre authority="marcgt">humor, satire</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'m')">
				<genre authority="marcgt">memoir</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'p')">
				<genre authority="marcgt">poetry</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'r')">
				<genre authority="marcgt">rehearsal</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'g')">
				<genre authority="marcgt">reporting</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'s')">
				<genre authority="marcgt">sound</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'l')">
				<genre authority="marcgt">speech</genre>
			</xsl:if>
		</xsl:if>
		<xsl:if test="$typeOf008='VM'">
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-33='a'">
					<genre authority="marcgt">art original</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='b'">
					<genre authority="marcgt">kit</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marcgt">art reproduction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marcgt">diorama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marcgt">filmstrip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='g'">
					<genre authority="marcgt">legal article</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marcgt">picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='k'">
					<genre authority="marcgt">graphic</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marcgt">technical drawing</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='m'">
					<genre authority="marcgt">motion picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='n'">
					<genre authority="marcgt">chart</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='o'">
					<genre authority="marcgt">flash card</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='p'">
					<genre authority="marcgt">microscope slide</genre>
				</xsl:when>
				<xsl:when
					test="$controlField008-33='q' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
					<genre authority="marcgt">model</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='r'">
					<genre authority="marcgt">realia</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marcgt">slide</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='t'">
					<genre authority="marcgt">transparency</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='v'">
					<genre authority="marcgt">videorecording</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='w'">
					<genre authority="marcgt">toy</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>

		<!-- 1.20 047 genre tmee-->

		<xsl:for-each select="marc:datafield[@tag=047]">
			<genre authority="marcgt">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcdef</xsl:with-param>
					<xsl:with-param name="delimeter">-</xsl:with-param>
				</xsl:call-template>
			</genre>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=655]">
			<genre authority="marcgt">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abvxyz</xsl:with-param>
					<xsl:with-param name="delimeter">-</xsl:with-param>
				</xsl:call-template>
			</genre>
		</xsl:for-each>
		<originInfo>
			<xsl:variable name="MARCpublicationCode"
				select="normalize-space(substring($controlField008,16,3))"/>
			<xsl:if test="translate($MARCpublicationCode,'|','')">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">marccountry</xsl:attribute>
						<xsl:value-of select="$MARCpublicationCode"/>
					</placeTerm>
				</place>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=044]/marc:subfield[@code='c']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">iso3166</xsl:attribute>
						<xsl:value-of select="."/>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=260]/marc:subfield[@code='a']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">text</xsl:attribute>
						<xsl:call-template name="chopPunctuationFront">
							<xsl:with-param name="chopString">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."/>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='m']">
				<dateValid point="start">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='n']">
				<dateValid point="end">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='j']">
				<dateModified>
					<xsl:value-of select="."/>
				</dateModified>
			</xsl:for-each>
			<xsl:for-each
				select="marc:datafield[@tag=260]/marc:subfield[@code='b' or @code='c' or @code='g']">
				<xsl:choose>
					<xsl:when test="@code='b'">
						<publisher>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
								<xsl:with-param name="punctuation">
									<xsl:text>:,;/ </xsl:text>
								</xsl:with-param>
							</xsl:call-template>
						</publisher>
					</xsl:when>
					<xsl:when test="@code='c'">
						<dateIssued>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</dateIssued>
					</xsl:when>
					<xsl:when test="@code='g'">
						<dateCreated>
							<xsl:value-of select="."/>
						</dateCreated>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<xsl:variable name="dataField260c">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString"
						select="marc:datafield[@tag=260]/marc:subfield[@code='c']"/>
				</xsl:call-template>
			</xsl:variable>
			<xsl:variable name="controlField008-7-10"
				select="normalize-space(substring($controlField008, 8, 4))"/>
			<xsl:variable name="controlField008-11-14"
				select="normalize-space(substring($controlField008, 12, 4))"/>
			<xsl:variable name="controlField008-6"
				select="normalize-space(substring($controlField008, 7, 1))"/>
			<xsl:if
				test="$controlField008-6='e' or $controlField008-6='p' or $controlField008-6='r' or $controlField008-6='t' or $controlField008-6='s'">
				<xsl:if test="$controlField008-7-10 and ($controlField008-7-10 != $dataField260c)">
					<dateIssued encoding="marc">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if
				test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if
				test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start" qualifier="questionable">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end" qualifier="questionable">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='t'">
				<xsl:if test="$controlField008-11-14">
					<copyrightDate encoding="marc">
						<xsl:value-of select="$controlField008-11-14"/>
					</copyrightDate>
				</xsl:if>
			</xsl:if>
			<xsl:for-each
				select="marc:datafield[@tag=033][@ind1=0 or @ind1=1]/marc:subfield[@code='a']">
				<dateCaptured encoding="iso8601">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][1]">
				<dateCaptured encoding="iso8601" point="start">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][2]">
				<dateCaptured encoding="iso8601" point="end">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=250]/marc:subfield[@code='a']">
				<edition>
					<xsl:value-of select="."/>
				</edition>
			</xsl:for-each>
			<xsl:for-each select="marc:leader">
				<issuance>
					<xsl:choose>
						<xsl:when
							test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'"
							>monographic</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'"
						>continuing</xsl:when>
					</xsl:choose>
				</issuance>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=310]|marc:datafield[@tag=321]">
				<frequency>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">ab</xsl:with-param>
					</xsl:call-template>
				</frequency>
			</xsl:for-each>
		</originInfo>
		<xsl:variable name="controlField008-35-37"
			select="normalize-space(translate(substring($controlField008,36,3),'|#',''))"/>
		<xsl:if test="$controlField008-35-37">
			<language>
				<languageTerm authority="iso639-2b" type="code">
					<xsl:value-of select="substring($controlField008,36,3)"/>
				</languageTerm>
			</language>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=041]">
			<xsl:for-each
				select="marc:subfield[@code='a' or @code='b' or @code='d' or @code='e' or @code='f' or @code='g' or @code='h']">
				<xsl:variable name="langCodes" select="."/>
				<xsl:choose>
					<xsl:when test="../marc:subfield[@code='2']='rfc3066'">
						<!-- not stacked but could be repeated -->
						<xsl:call-template name="rfcLanguages">
							<xsl:with-param name="nodeNum">
								<xsl:value-of select="1"/>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:text/>
							</xsl:with-param>
							<xsl:with-param name="controlField008-35-37">
								<xsl:value-of select="$controlField008-35-37"/>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:when>
					<xsl:otherwise>
						<!-- iso -->
						<xsl:variable name="allLanguages">
							<xsl:copy-of select="$langCodes"/>
						</xsl:variable>
						<xsl:variable name="currentLanguage">
							<xsl:value-of select="substring($allLanguages,1,3)"/>
						</xsl:variable>
						<xsl:call-template name="isoLanguage">
							<xsl:with-param name="currentLanguage">
								<xsl:value-of select="substring($allLanguages,1,3)"/>
							</xsl:with-param>
							<xsl:with-param name="remainingLanguages">
								<xsl:value-of
									select="substring($allLanguages,4,string-length($allLanguages)-3)"
								/>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:if test="$controlField008-35-37">
									<xsl:value-of select="$controlField008-35-37"/>
								</xsl:if>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:variable name="physicalDescription">
			<!--3.2 change tmee 007/11 -->
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='a']">
				<digitalOrigin>reformatted digital</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='b']">
				<digitalOrigin>digitized microfilm</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='d']">
				<digitalOrigin>digitized other analog</digitalOrigin>
			</xsl:if>
			<xsl:variable name="controlField008-23" select="substring($controlField008,24,1)"/>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"/>
			<xsl:variable name="check008-23">
				<xsl:if
					test="$typeOf008='BK' or $typeOf008='MU' or $typeOf008='SE' or $typeOf008='MM'">
					<xsl:value-of select="true()"/>
				</xsl:if>
			</xsl:variable>
			<xsl:variable name="check008-29">
				<xsl:if test="$typeOf008='MP' or $typeOf008='VM'">
					<xsl:value-of select="true()"/>
				</xsl:if>
			</xsl:variable>
			<xsl:choose>
				<xsl:when
					test="($check008-23 and $controlField008-23='f') or ($check008-29 and $controlField008-29='f')">
					<form authority="marcform">braille</form>
				</xsl:when>
				<xsl:when
					test="($controlField008-23=' ' and ($leader6='c' or $leader6='d')) or (($typeOf008='BK' or $typeOf008='SE') and ($controlField008-23=' ' or $controlField008='r'))">
					<form authority="marcform">print</form>
				</xsl:when>
				<xsl:when
					test="$leader6 = 'm' or ($check008-23 and $controlField008-23='s') or ($check008-29 and $controlField008-29='s')">
					<form authority="marcform">electronic</form>
				</xsl:when>
				<xsl:when
					test="($check008-23 and $controlField008-23='b') or ($check008-29 and $controlField008-29='b')">
					<form authority="marcform">microfiche</form>
				</xsl:when>
				<xsl:when
					test="($check008-23 and $controlField008-23='a') or ($check008-29 and $controlField008-29='a')">
					<form authority="marcform">microfilm</form>
				</xsl:when>
			</xsl:choose>
			<!-- 1/04 fix -->
			<xsl:if test="marc:datafield[@tag=130]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=130]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=240]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=240]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=242]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=242]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=245]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=245]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=246]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=246]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=730]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=730]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=256]/marc:subfield[@code='a']">
				<form>
					<xsl:value-of select="."/>
				</form>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=007][substring(text(),1,1)='c']">
				<xsl:choose>
					<xsl:when test="substring(text(),14,1)='a'">
						<reformattingQuality>access</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='p'">
						<reformattingQuality>preservation</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='r'">
						<reformattingQuality>replacement</reformattingQuality>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<!--3.2 change tmee 007/01 -->
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='b']">
				<form authority="smd">chip cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='c']">
				<form authority="smd">computer optical disc cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='j']">
				<form authority="smd">magnetic disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='m']">
				<form authority="smd">magneto-optical disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='o']">
				<form authority="smd">optical disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='r']">
				<form authority="smd">remote</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='a']">
				<form authority="smd">tape cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='f']">
				<form authority="smd">tape cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='h']">
				<form authority="smd">tape reel</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='a']">
				<form authority="smd">celestial globe</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='e']">
				<form authority="smd">earth moon globe</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='b']">
				<form authority="smd">planetary or lunar globe</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='c']">
				<form authority="smd">terrestrial globe</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='o'][substring(text(),2,1)='o']">
				<form authority="smd">kit</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
				<form authority="smd">atlas</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='g']">
				<form authority="smd">diagram</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
				<form authority="smd">map</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
				<form authority="smd">model</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='k']">
				<form authority="smd">profile</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='s']">
				<form authority="smd">section</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='y']">
				<form authority="smd">view</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='a']">
				<form authority="smd">aperture card</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='e']">
				<form authority="smd">microfiche</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='f']">
				<form authority="smd">microfiche cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='b']">
				<form authority="smd">microfilm cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='c']">
				<form authority="smd">microfilm cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='d']">
				<form authority="smd">microfilm reel</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='g']">
				<form authority="smd">microopaque</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='c']">
				<form authority="smd">film cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='f']">
				<form authority="smd">film cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='r']">
				<form authority="smd">film reel</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='n']">
				<form authority="smd">chart</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='c']">
				<form authority="smd">collage</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='d']">
				<form authority="smd">drawing</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='o']">
				<form authority="smd">flash card</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='e']">
				<form authority="smd">painting</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='f']">
				<form authority="smd">photomechanical print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='g']">
				<form authority="smd">photonegative</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='h']">
				<form authority="smd">photoprint</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='i']">
				<form authority="smd">picture</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='j']">
				<form authority="smd">print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='l']">
				<form authority="smd">technical drawing</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='q'][substring(text(),2,1)='q']">
				<form authority="smd">notated music</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='d']">
				<form authority="smd">filmslip</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='c']">
				<form authority="smd">filmstrip cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='o']">
				<form authority="smd">filmstrip roll</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='f']">
				<form authority="smd">other filmstrip type</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='s']">
				<form authority="smd">slide</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='t']">
				<form authority="smd">transparency</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='r'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='e']">
				<form authority="smd">cylinder</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='q']">
				<form authority="smd">roll</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='g']">
				<form authority="smd">sound cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='s']">
				<form authority="smd">sound cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='d']">
				<form authority="smd">sound disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='t']">
				<form authority="smd">sound-tape reel</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='i']">
				<form authority="smd">sound-track film</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='w']">
				<form authority="smd">wire recording</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='b']">
				<form authority="smd">combination</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='a']">
				<form authority="smd">moon</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='d']">
				<form authority="smd">tactile, with no writing system</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='b']">
				<form authority="smd">large print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='a']">
				<form authority="smd">regular print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='d']">
				<form authority="smd">text in looseleaf binder</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='c']">
				<form authority="smd">videocartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='f']">
				<form authority="smd">videocassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='d']">
				<form authority="smd">videodisc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='r']">
				<form authority="smd">videoreel</form>
			</xsl:if>

			<xsl:for-each
				select="marc:datafield[@tag=856]/marc:subfield[@code='q'][string-length(.)&gt;1]">
				<internetMediaType>
					<xsl:value-of select="."/>
				</internetMediaType>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=300]">
				<extent>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abce</xsl:with-param>
					</xsl:call-template>
				</extent>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($physicalDescription))">
			<physicalDescription>
				<xsl:copy-of select="$physicalDescription"/>
			</physicalDescription>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=520]">
			<abstract>
				<xsl:call-template name="uri"/>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</abstract>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=505]">
			<tableOfContents>
				<xsl:call-template name="uri"/>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">agrt</xsl:with-param>
				</xsl:call-template>
			</tableOfContents>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=521]">
			<targetAudience>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</targetAudience>
		</xsl:for-each>
		<xsl:if test="$typeOf008='BK' or $typeOf008='CF' or $typeOf008='MU' or $typeOf008='VM'">
			<xsl:variable name="controlField008-22" select="substring($controlField008,23,1)"/>
			<xsl:choose>
				<!-- 01/04 fix -->
				<xsl:when test="$controlField008-22='d'">
					<targetAudience authority="marctarget">adolescent</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='e'">
					<targetAudience authority="marctarget">adult</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='g'">
					<targetAudience authority="marctarget">general</targetAudience>
				</xsl:when>
				<xsl:when
					test="$controlField008-22='b' or $controlField008-22='c' or $controlField008-22='j'">
					<targetAudience authority="marctarget">juvenile</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='a'">
					<targetAudience authority="marctarget">preschool</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='f'">
					<targetAudience authority="marctarget">specialized</targetAudience>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=245]/marc:subfield[@code='c']">
			<note type="statement of responsibility">
				<xsl:value-of select="."/>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=500]">
			<note>
				<xsl:value-of select="marc:subfield[@code='a']"/>
				<xsl:call-template name="uri"/>
			</note>
		</xsl:for-each>

		<!--3.2 change tmee additional note fields-->

		<xsl:for-each select="marc:datafield[@tag=506]">
			<note type="restrictions">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=510]">
			<note type="citation/reference">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>


		<xsl:for-each select="marc:datafield[@tag=511]">
			<note type="performers">
				<xsl:call-template name="uri"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=518]">
			<note type="venue">
				<xsl:call-template name="uri"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=530]">
			<note type="additional physical form">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=533]">
			<note type="reproduction">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=534]">
			<note type="original version">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=538]">
			<note type="system details">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=583]">
			<note type="action">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each
			select="marc:datafield[@tag=501 or @tag=502 or @tag=504 or @tag=507 or @tag=508 or  @tag=513 or @tag=514 or @tag=515 or @tag=516 or @tag=522 or @tag=524 or @tag=525 or @tag=526 or @tag=535 or @tag=536 or @tag=540 or @tag=541 or @tag=544 or @tag=545 or @tag=546 or @tag=547 or @tag=550 or @tag=552 or @tag=555 or @tag=556 or @tag=561 or @tag=562 or @tag=565 or @tag=567 or @tag=580 or @tag=581 or @tag=584 or @tag=585 or @tag=586]">
			<note>
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>
		<xsl:for-each
			select="marc:datafield[@tag=034][marc:subfield[@code='d' or @code='e' or @code='f' or @code='g']]">
			<subject>
				<cartographics>
					<coordinates>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">defg</xsl:with-param>
						</xsl:call-template>
					</coordinates>
				</cartographics>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=043]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
					<geographicCode>
						<xsl:attribute name="authority">
							<xsl:if test="@code='a'">
								<xsl:text>marcgac</xsl:text>
							</xsl:if>
							<xsl:if test="@code='b'">
								<xsl:value-of select="following-sibling::marc:subfield[@code=2]"/>
							</xsl:if>
							<xsl:if test="@code='c'">
								<xsl:text>iso3166</xsl:text>
							</xsl:if>
						</xsl:attribute>
						<xsl:value-of select="self::marc:subfield"/>
					</geographicCode>
				</xsl:for-each>
			</subject>
		</xsl:for-each>
		<!-- tmee 2006/11/27 -->
		<xsl:for-each select="marc:datafield[@tag=255]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
					<cartographics>
						<xsl:if test="@code='a'">
							<scale>
								<xsl:value-of select="."/>
							</scale>
						</xsl:if>
						<xsl:if test="@code='b'">
							<projection>
								<xsl:value-of select="."/>
							</projection>
						</xsl:if>
						<xsl:if test="@code='c'">
							<coordinates>
								<xsl:value-of select="."/>
							</coordinates>
						</xsl:if>
					</cartographics>
				</xsl:for-each>
			</subject>
		</xsl:for-each>

		<xsl:apply-templates select="marc:datafield[653 &gt;= @tag and @tag &gt;= 600]"/>
		<xsl:apply-templates select="marc:datafield[@tag=656]"/>
		<xsl:for-each select="marc:datafield[@tag=752 or @tag=662]">
			<subject>
				<hierarchicalGeographic>
					<xsl:for-each select="marc:subfield[@code='a']">
						<country>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</country>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<state>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</state>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='c']">
						<county>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</county>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='d']">
						<city>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</city>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='e']">
						<citySection>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</citySection>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='g']">
						<region>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</region>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='h']">
						<extraterrestrialArea>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</extraterrestrialArea>
					</xsl:for-each>
				</hierarchicalGeographic>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=045][marc:subfield[@code='b']]">
			<subject>
				<xsl:choose>
					<xsl:when test="@ind1=2">
						<temporal encoding="iso8601" point="start">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][1]"/>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
						<temporal encoding="iso8601" point="end">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][2]"/>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
					</xsl:when>
					<xsl:otherwise>
						<xsl:for-each select="marc:subfield[@code='b']">
							<temporal encoding="iso8601">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."/>
								</xsl:call-template>
							</temporal>
						</xsl:for-each>
					</xsl:otherwise>
				</xsl:choose>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=050]">
			<xsl:for-each select="marc:subfield[@code='b']">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"/>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="preceding-sibling::marc:subfield[@code='a'][1]"/>
					<xsl:text> </xsl:text>
					<xsl:value-of select="text()"/>
				</classification>
			</xsl:for-each>
			<xsl:for-each
				select="marc:subfield[@code='a'][not(following-sibling::marc:subfield[@code='b'])]">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"/>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="text()"/>
				</classification>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=082]">
			<classification authority="ddc">
				<xsl:if test="marc:subfield[@code='2']">
					<xsl:attribute name="edition">
						<xsl:value-of select="marc:subfield[@code='2']"/>
					</xsl:attribute>
				</xsl:if>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=080]">
			<classification authority="udc">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abx</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=060]">
			<classification authority="nlm">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=0]">
			<classification authority="sudocs">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=1]">
			<classification authority="candoc">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=084]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=440]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=490][@ind1=0]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=510]">
			<relatedItem type="isReferencedBy">
				<note>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcx3</xsl:with-param>
					</xsl:call-template>
				</note>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=534]">
			<relatedItem type="original">
				<xsl:call-template name="relatedTitle"/>
				<xsl:call-template name="relatedName"/>
				<xsl:if test="marc:subfield[@code='b' or @code='c']">
					<originInfo>
						<xsl:for-each select="marc:subfield[@code='c']">
							<publisher>
								<xsl:value-of select="."/>
							</publisher>
						</xsl:for-each>
						<xsl:for-each select="marc:subfield[@code='b']">
							<edition>
								<xsl:value-of select="."/>
							</edition>
						</xsl:for-each>
					</originInfo>
				</xsl:if>
				<xsl:call-template name="relatedIdentifierISSN"/>
				<xsl:for-each select="marc:subfield[@code='z']">
					<identifier type="isbn">
						<xsl:value-of select="."/>
					</identifier>
				</xsl:for-each>
				<xsl:call-template name="relatedNote"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=700][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aq</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">g</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"/>
					<xsl:call-template name="nameDate"/>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=710][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<xsl:variable name="tempNamePart">
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</xsl:variable>
					<xsl:if test="normalize-space($tempNamePart)">
						<namePart>
							<xsl:value-of select="$tempNamePart"/>
						</namePart>
					</xsl:if>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=711][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</name>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=730][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=740][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:value-of select="marc:subfield[@code='a']"/>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=760]|marc:datafield[@tag=762]">
			<relatedItem type="series">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each
			select="marc:datafield[@tag=765]|marc:datafield[@tag=767]|marc:datafield[@tag=777]|marc:datafield[@tag=787]">
			<relatedItem>
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=775]">
			<relatedItem type="otherVersion">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=770]|marc:datafield[@tag=774]">
			<relatedItem type="constituent">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=772]|marc:datafield[@tag=773]">
			<relatedItem type="host">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=776]">
			<relatedItem type="otherFormat">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=780]">
			<relatedItem type="preceding">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=785]">
			<relatedItem type="succeeding">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=786]">
			<relatedItem type="original">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=800]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">aq</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="beforeCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"/>
					<xsl:call-template name="nameDate"/>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=810]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=811]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='830']">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][@ind2='2']/marc:subfield[@code='q']">
			<relatedItem>
				<internetMediaType>
					<xsl:value-of select="."/>
				</internetMediaType>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='020']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isbn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isbn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='0']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isrc</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isrc">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='2']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">ismn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="ismn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='4']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">sici</xsl:with-param>
			</xsl:call-template>
			<identifier type="sici">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='022']">
			<xsl:if test="marc:subfield[@code='a']">
				<xsl:call-template name="isInvalid">
					<xsl:with-param name="type">issn</xsl:with-param>
				</xsl:call-template>
				<identifier type="issn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
			<xsl:if test="marc:subfield[@code='l']">
				<xsl:call-template name="isInvalid">
					<xsl:with-param name="type">issn-l</xsl:with-param>
				</xsl:call-template>
				<identifier type="issn-l">
					<xsl:value-of select="marc:subfield[@code='l']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>



		<xsl:for-each select="marc:datafield[@tag='010']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">lccn</xsl:with-param>
			</xsl:call-template>
			<identifier type="lccn">
				<xsl:value-of select="normalize-space(marc:subfield[@code='a'])"/>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='028']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when test="@ind1='0'">issue number</xsl:when>
						<xsl:when test="@ind1='1'">matrix number</xsl:when>
						<xsl:when test="@ind1='2'">music plate</xsl:when>
						<xsl:when test="@ind1='3'">music publisher</xsl:when>
						<xsl:when test="@ind1='4'">videorecording identifier</xsl:when>
					</xsl:choose>
				</xsl:attribute>
				<!--<xsl:call-template name="isInvalid"/>-->
				<!-- no $z in 028 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">
						<xsl:choose>
							<xsl:when test="@ind1='0'">ba</xsl:when>
							<xsl:otherwise>ab</xsl:otherwise>
						</xsl:choose>
					</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='037']">
			<identifier type="stock number">
				<!--<xsl:call-template name="isInvalid"/>-->
				<!-- no $z in 037 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][marc:subfield[@code='u']]">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when
							test="starts-with(marc:subfield[@code='u'],'urn:doi') or starts-with(marc:subfield[@code='u'],'doi')"
							>doi</xsl:when>
						<xsl:when
							test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov')"
							>hdl</xsl:when>
						<xsl:otherwise>uri</xsl:otherwise>
					</xsl:choose>
				</xsl:attribute>
				<xsl:choose>
					<xsl:when
						test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov') ">
						<xsl:value-of
							select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"
						/>
					</xsl:when>
					<xsl:otherwise>
						<xsl:value-of select="marc:subfield[@code='u']"/>
					</xsl:otherwise>
				</xsl:choose>
			</identifier>
			<xsl:if
				test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl')">
				<identifier type="hdl">
					<xsl:if test="marc:subfield[@code='y' or @code='3' or @code='z']">
						<xsl:attribute name="displayLabel">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">y3z</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of
						select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"
					/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=024][@ind1=1]">
			<identifier type="upc">
				<xsl:call-template name="isInvalid"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</identifier>
		</xsl:for-each>

		<!-- 1/04 fix added $y -->

		<!-- 1.21  tmee-->
		<xsl:for-each select="marc:datafield[@tag=856][@ind2=1][marc:subfield[@code='u']]">
			<relatedItem type="otherVersion">
				<location>
					<url>
						<xsl:if test="marc:subfield[@code='y' or @code='3']">
							<xsl:attribute name="displayLabel">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">y3</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:if test="marc:subfield[@code='z' ]">
							<xsl:attribute name="note">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">z</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:value-of select="marc:subfield[@code='u']"/>
					</url>
				</location>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=856][@ind2=2][marc:subfield[@code='u']]">
			<relatedItem>
				<location>
					<url>
						<xsl:if test="marc:subfield[@code='y' or @code='3']">
							<xsl:attribute name="displayLabel">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">y3</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:if test="marc:subfield[@code='z' ]">
							<xsl:attribute name="note">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">z</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:value-of select="marc:subfield[@code='u']"/>
					</url>
				</location>
			</relatedItem>
		</xsl:for-each>

		<!-- 3.2 change tmee 856z  -->

		<!-- 1.24  tmee  -->
		<xsl:for-each select="marc:datafield[@tag=852]">
			<location>
				<xsl:if test="marc:subfield[@code='a' or @code='b' or @code='e']">
					<physicalLocation>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abe</xsl:with-param>
						</xsl:call-template>
					</physicalLocation>
				</xsl:if>

				<xsl:if test="marc:subfield[@code='u']">
					<physicalLocation>
						<xsl:call-template name="uri"/>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">u</xsl:with-param>
						</xsl:call-template>
					</physicalLocation>
				</xsl:if>

				<xsl:if
					test="marc:subfield[@code='h' or @code='i' or @code='j' or @code='k' or @code='l' or @code='m' or @code='t']">
					<shelfLocation>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">hijklmt</xsl:with-param>
						</xsl:call-template>
					</shelfLocation>
				</xsl:if>
			</location>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=506]">
			<accessCondition type="restrictionOnAccess">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcd35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=540]">
			<accessCondition type="useAndReproduction">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcde35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>

		<recordInfo>
			<!-- 1.25  tmee-->


			<xsl:for-each select="marc:leader[substring($leader,19,1)='a']">
				<descriptionStandard>aacr2</descriptionStandard>
			</xsl:for-each>

			<xsl:for-each select="marc:datafield[@tag=040]">
				<xsl:if test="marc:subfield[@code='e']">
					<descriptionStandard>
						<xsl:value-of select="marc:subfield[@code='e']"/>
					</descriptionStandard>
				</xsl:if>
				<recordContentSource authority="marcorg">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</recordContentSource>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=008]">
				<recordCreationDate encoding="marc">
					<xsl:value-of select="substring(.,1,6)"/>
				</recordCreationDate>
			</xsl:for-each>

			<xsl:for-each select="marc:controlfield[@tag=005]">
				<recordChangeDate encoding="iso8601">
					<xsl:value-of select="."/>
				</recordChangeDate>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=001]">
				<recordIdentifier>
					<xsl:if test="../marc:controlfield[@tag=003]">
						<xsl:attribute name="source">
							<xsl:value-of select="../marc:controlfield[@tag=003]"/>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="."/>
				</recordIdentifier>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=040]/marc:subfield[@code='b']">
				<languageOfCataloging>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="."/>
					</languageTerm>
				</languageOfCataloging>
			</xsl:for-each>
		</recordInfo>
	</xsl:template>
	<xsl:template name="displayForm">
		<xsl:for-each select="marc:subfield[@code='c']">
			<displayForm>
				<xsl:value-of select="."/>
			</displayForm>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="affiliation">
		<xsl:for-each select="marc:subfield[@code='u']">
			<affiliation>
				<xsl:value-of select="."/>
			</affiliation>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="uri">
		<xsl:for-each select="marc:subfield[@code='u']|marc:subfield[@code='0']">
			<xsl:attribute name="xlink:href">
				<xsl:value-of select="."/>
			</xsl:attribute>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="role">
		<xsl:for-each select="marc:subfield[@code='e']">
			<role>
				<roleTerm type="text">
					<xsl:value-of select="."/>
				</roleTerm>
			</role>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='4']">
			<role>
				<roleTerm authority="marcrelator" type="code">
					<xsl:value-of select="."/>
				</roleTerm>
			</role>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="part">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">n</xsl:with-param>
				<xsl:with-param name="anyCodes">n</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partNumber"/>
				</xsl:call-template>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partName"/>
				</xsl:call-template>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPart">
		<xsl:if test="@tag=773">
			<xsl:for-each select="marc:subfield[@code='g']">
				<part>
					<text>
						<xsl:value-of select="."/>
					</text>
				</part>
			</xsl:for-each>
			<xsl:for-each select="marc:subfield[@code='q']">
				<part>
					<xsl:call-template name="parsePart"/>
				</part>
			</xsl:for-each>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPartNumName">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">g</xsl:with-param>
				<xsl:with-param name="anyCodes">g</xsl:with-param>
				<xsl:with-param name="afterCodes">pst</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:value-of select="$partNumber"/>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:value-of select="$partName"/>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedName">
		<xsl:for-each select="marc:subfield[@code='a']">
			<name>
				<namePart>
					<xsl:value-of select="."/>
				</namePart>
			</name>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedForm">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<form>
					<xsl:value-of select="."/>
				</form>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedExtent">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<extent>
					<xsl:value-of select="."/>
				</extent>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedNote">
		<xsl:for-each select="marc:subfield[@code='n']">
			<note>
				<xsl:value-of select="."/>
			</note>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedSubject">
		<xsl:for-each select="marc:subfield[@code='j']">
			<subject>
				<temporal encoding="iso8601">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."/>
					</xsl:call-template>
				</temporal>
			</subject>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierISSN">
		<xsl:for-each select="marc:subfield[@code='x']">
			<identifier type="issn">
				<xsl:value-of select="."/>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierLocal">
		<xsl:for-each select="marc:subfield[@code='w']">
			<identifier type="local">
				<xsl:value-of select="."/>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifier">
		<xsl:for-each select="marc:subfield[@code='o']">
			<identifier>
				<xsl:value-of select="."/>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedItem76X-78X">
		<xsl:call-template name="displayLabel"/>
		<xsl:call-template name="relatedTitle76X-78X"/>
		<xsl:call-template name="relatedName"/>
		<xsl:call-template name="relatedOriginInfo"/>
		<xsl:call-template name="relatedLanguage"/>
		<xsl:call-template name="relatedExtent"/>
		<xsl:call-template name="relatedNote"/>
		<xsl:call-template name="relatedSubject"/>
		<xsl:call-template name="relatedIdentifier"/>
		<xsl:call-template name="relatedIdentifierISSN"/>
		<xsl:call-template name="relatedIdentifierLocal"/>
		<xsl:call-template name="relatedPart"/>
	</xsl:template>
	<xsl:template name="subjectGeographicZ">
		<geographic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</geographic>
	</xsl:template>
	<xsl:template name="subjectTemporalY">
		<temporal>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</temporal>
	</xsl:template>
	<xsl:template name="subjectTopic">
		<topic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</topic>
	</xsl:template>
	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template name="subjectGenre">
		<genre>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</genre>
	</xsl:template>

	<xsl:template name="nameABCDN">
		<xsl:for-each select="marc:subfield[@code='a']">
			<namePart>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='b']">
			<namePart>
				<xsl:value-of select="."/>
			</namePart>
		</xsl:for-each>
		<xsl:if
			test="marc:subfield[@code='c'] or marc:subfield[@code='d'] or marc:subfield[@code='n']">
			<namePart>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">cdn</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="nameABCDQ">
		<namePart>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">aq</xsl:with-param>
					</xsl:call-template>
				</xsl:with-param>
				<xsl:with-param name="punctuation">
					<xsl:text>:,;/ </xsl:text>
				</xsl:with-param>
			</xsl:call-template>
		</namePart>
		<xsl:call-template name="termsOfAddress"/>
		<xsl:call-template name="nameDate"/>
	</xsl:template>
	<xsl:template name="nameACDEQ">
		<namePart>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">acdeq</xsl:with-param>
			</xsl:call-template>
		</namePart>
	</xsl:template>
	<xsl:template name="constituentOrRelatedType">
		<xsl:if test="@ind2=2">
			<xsl:attribute name="type">constituent</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedTitle">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedTitle76X-78X">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"/>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='p']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"/>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='s']">
			<titleInfo type="uniform">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"/>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedOriginInfo">
		<xsl:if test="marc:subfield[@code='b' or @code='d'] or marc:subfield[@code='f']">
			<originInfo>
				<xsl:if test="@tag=775">
					<xsl:for-each select="marc:subfield[@code='f']">
						<place>
							<placeTerm>
								<xsl:attribute name="type">code</xsl:attribute>
								<xsl:attribute name="authority">marcgac</xsl:attribute>
								<xsl:value-of select="."/>
							</placeTerm>
						</place>
					</xsl:for-each>
				</xsl:if>
				<xsl:for-each select="marc:subfield[@code='d']">
					<publisher>
						<xsl:value-of select="."/>
					</publisher>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<edition>
						<xsl:value-of select="."/>
					</edition>
				</xsl:for-each>
			</originInfo>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedLanguage">
		<xsl:for-each select="marc:subfield[@code='e']">
			<xsl:call-template name="getLanguage">
				<xsl:with-param name="langString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="nameDate">
		<xsl:for-each select="marc:subfield[@code='d']">
			<namePart type="date">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="subjectAuthority">
		<xsl:if test="@ind2!=4">
			<xsl:if test="@ind2!=' '">
				<xsl:if test="@ind2!=8">
					<xsl:if test="@ind2!=9">
						<xsl:attribute name="authority">
							<xsl:choose>
								<xsl:when test="@ind2=0">lcsh</xsl:when>
								<xsl:when test="@ind2=1">lcshac</xsl:when>
								<xsl:when test="@ind2=2">mesh</xsl:when>
								<!-- 1/04 fix -->
								<xsl:when test="@ind2=3">nal</xsl:when>
								<xsl:when test="@ind2=5">csh</xsl:when>
								<xsl:when test="@ind2=6">rvm</xsl:when>
								<xsl:when test="@ind2=7">
									<xsl:value-of select="marc:subfield[@code='2']"/>
								</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
				</xsl:if>
			</xsl:if>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subjectAnyOrder">
		<xsl:for-each select="marc:subfield[@code='v' or @code='x' or @code='y' or @code='z']">
			<xsl:choose>
				<xsl:when test="@code='v'">
					<xsl:call-template name="subjectGenre"/>
				</xsl:when>
				<xsl:when test="@code='x'">
					<xsl:call-template name="subjectTopic"/>
				</xsl:when>
				<xsl:when test="@code='y'">
					<xsl:call-template name="subjectTemporalY"/>
				</xsl:when>
				<xsl:when test="@code='z'">
					<xsl:call-template name="subjectGeographicZ"/>
				</xsl:when>
			</xsl:choose>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="specialSubfieldSelect">
		<xsl:param name="anyCodes"/>
		<xsl:param name="axis"/>
		<xsl:param name="beforeCodes"/>
		<xsl:param name="afterCodes"/>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if
					test="contains($anyCodes, @code)      or (contains($beforeCodes,@code) and following-sibling::marc:subfield[@code=$axis])      or (contains($afterCodes,@code) and preceding-sibling::marc:subfield[@code=$axis])">
					<xsl:value-of select="text()"/>
					<xsl:text> </xsl:text>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
	</xsl:template>

	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template match="marc:datafield[@tag=600]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<name type="personal">
				<xsl:call-template name="termsOfAddress"/>
				<namePart>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">aq</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:call-template name="nameDate"/>
				<xsl:call-template name="affiliation"/>
				<xsl:call-template name="role"/>
			</name>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=610]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<name type="corporate">
				<xsl:for-each select="marc:subfield[@code='a']">
					<namePart>
						<xsl:value-of select="."/>
					</namePart>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<namePart>
						<xsl:value-of select="."/>
					</namePart>
				</xsl:for-each>
				<xsl:if test="marc:subfield[@code='c' or @code='d' or @code='n' or @code='p']">
					<namePart>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">cdnp</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</xsl:if>
				<xsl:call-template name="role"/>
			</name>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=611]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<name type="conference">
				<namePart>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcdeqnp</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:for-each select="marc:subfield[@code='4']">
					<role>
						<roleTerm authority="marcrelator" type="code">
							<xsl:value-of select="."/>
						</roleTerm>
					</role>
				</xsl:for-each>
			</name>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=630]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">adfhklor</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<!-- 1.27 648 tmee-->
	<xsl:template match="marc:datafield[@tag=648]">
		<subject>
			<xsl:if test="marc:subfield[@code=2]">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code=2]"/>
				</xsl:attribute>
			</xsl:if>
			<xsl:call-template name="uri"/>

			<xsl:call-template name="subjectAuthority"/>
			<temporal>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abcd</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</temporal>
			<xsl:call-template name="subjectAnyOrder"/>

		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=650]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<topic>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abcd</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</topic>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=651]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<xsl:for-each select="marc:subfield[@code='a']">
				<geographic>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."/>
					</xsl:call-template>
				</geographic>
			</xsl:for-each>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=653]">
		<subject>
			<xsl:for-each select="marc:subfield[@code='a']">
				<topic>
					<xsl:value-of select="."/>
				</topic>
			</xsl:for-each>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=656]">
		<subject>
			<xsl:if test="marc:subfield[@code=2]">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code=2]"/>
				</xsl:attribute>
			</xsl:if>
			<occupation>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</xsl:with-param>
				</xsl:call-template>
			</occupation>
		</subject>
	</xsl:template>
	<xsl:template name="termsOfAddress">
		<xsl:if test="marc:subfield[@code='b' or @code='c']">
			<namePart type="termsOfAddress">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">bc</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="displayLabel">
		<xsl:if test="marc:subfield[@code='i']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='i']"/>
			</xsl:attribute>
		</xsl:if>
		<xsl:if test="marc:subfield[@code='3']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='3']"/>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="isInvalid">
		<xsl:param name="type"/>
		<xsl:if
			test="marc:subfield[@code='z'] or marc:subfield[@code='y']  or marc:subfield[@code='m']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:value-of select="$type"/>
				</xsl:attribute>
				<xsl:attribute name="invalid">
					<xsl:text>yes</xsl:text>
				</xsl:attribute>
				<xsl:if test="marc:subfield[@code='z']">
					<xsl:value-of select="marc:subfield[@code='z']"/>
				</xsl:if>
				<xsl:if test="marc:subfield[@code='y']">
					<xsl:value-of select="marc:subfield[@code='y']"/>
				</xsl:if>
				<xsl:if test="marc:subfield[@code='m']">
					<xsl:value-of select="marc:subfield[@code='m']"/>
				</xsl:if>
			</identifier>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subtitle">
		<xsl:if test="marc:subfield[@code='b']">
			<subTitle>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='b']"/>
						<!--<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">b</xsl:with-param>									
						</xsl:call-template>-->
					</xsl:with-param>
				</xsl:call-template>
			</subTitle>
		</xsl:if>
	</xsl:template>
	<xsl:template name="script">
		<xsl:param name="scriptCode"/>
		<xsl:attribute name="script">
			<xsl:choose>
				<xsl:when test="$scriptCode='(3'">Arabic</xsl:when>
				<xsl:when test="$scriptCode='(B'">Latin</xsl:when>
				<xsl:when test="$scriptCode='$1'">Chinese, Japanese, Korean</xsl:when>
				<xsl:when test="$scriptCode='(N'">Cyrillic</xsl:when>
				<xsl:when test="$scriptCode='(2'">Hebrew</xsl:when>
				<xsl:when test="$scriptCode='(S'">Greek</xsl:when>
			</xsl:choose>
		</xsl:attribute>
	</xsl:template>
	<xsl:template name="parsePart">
		<!-- assumes 773$q= 1:2:3<4
		     with up to 3 levels and one optional start page
		-->
		<xsl:variable name="level1">
			<xsl:choose>
				<xsl:when test="contains(text(),':')">
					<!-- 1:2 -->
					<xsl:value-of select="substring-before(text(),':')"/>
				</xsl:when>
				<xsl:when test="not(contains(text(),':'))">
					<!-- 1 or 1<3 -->
					<xsl:if test="contains(text(),'&lt;')">
						<!-- 1<3 -->
						<xsl:value-of select="substring-before(text(),'&lt;')"/>
					</xsl:if>
					<xsl:if test="not(contains(text(),'&lt;'))">
						<!-- 1 -->
						<xsl:value-of select="text()"/>
					</xsl:if>
				</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici2">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after(text(),$level1),':')">
					<xsl:value-of select="substring(substring-after(text(),$level1),2)"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after(text(),$level1)"/>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level2">
			<xsl:choose>
				<xsl:when test="contains($sici2,':')">
					<!--  2:3<4  -->
					<xsl:value-of select="substring-before($sici2,':')"/>
				</xsl:when>
				<xsl:when test="contains($sici2,'&lt;')">
					<!-- 1: 2<4 -->
					<xsl:value-of select="substring-before($sici2,'&lt;')"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici2"/>
					<!-- 1:2 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici3">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after($sici2,$level2),':')">
					<xsl:value-of select="substring(substring-after($sici2,$level2),2)"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after($sici2,$level2)"/>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level3">
			<xsl:choose>
				<xsl:when test="contains($sici3,'&lt;')">
					<!-- 2<4 -->
					<xsl:value-of select="substring-before($sici3,'&lt;')"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici3"/>
					<!-- 3 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="page">
			<xsl:if test="contains(text(),'&lt;')">
				<xsl:value-of select="substring-after(text(),'&lt;')"/>
			</xsl:if>
		</xsl:variable>
		<xsl:if test="$level1">
			<detail level="1">
				<number>
					<xsl:value-of select="$level1"/>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level2">
			<detail level="2">
				<number>
					<xsl:value-of select="$level2"/>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level3">
			<detail level="3">
				<number>
					<xsl:value-of select="$level3"/>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$page">
			<extent unit="page">
				<start>
					<xsl:value-of select="$page"/>
				</start>
			</extent>
		</xsl:if>
	</xsl:template>
	<xsl:template name="getLanguage">
		<xsl:param name="langString"/>
		<xsl:param name="controlField008-35-37"/>
		<xsl:variable name="length" select="string-length($langString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="$controlField008-35-37=substring($langString,1,3)">
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"/>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<language>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="substring($langString,1,3)"/>
					</languageTerm>
				</language>
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"/>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"/>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="isoLanguage">
		<xsl:param name="currentLanguage"/>
		<xsl:param name="usedLanguages"/>
		<xsl:param name="remainingLanguages"/>
		<xsl:choose>
			<xsl:when test="string-length($currentLanguage)=0"/>
			<xsl:when test="not(contains($usedLanguages, $currentLanguage))">
				<language>
					<xsl:if test="@code!='a'">
						<xsl:attribute name="objectPart">
							<xsl:choose>
								<xsl:when test="@code='b'">summary or subtitle</xsl:when>
								<xsl:when test="@code='d'">sung or spoken text</xsl:when>
								<xsl:when test="@code='e'">libretto</xsl:when>
								<xsl:when test="@code='f'">table of contents</xsl:when>
								<xsl:when test="@code='g'">accompanying material</xsl:when>
								<xsl:when test="@code='h'">translation</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="$currentLanguage"/>
					</languageTerm>
				</language>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"/>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"/>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of
							select="substring($remainingLanguages,4,string-length($remainingLanguages))"
						/>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"/>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"/>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of
							select="substring($remainingLanguages,4,string-length($remainingLanguages))"
						/>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="chopBrackets">
		<xsl:param name="chopString"/>
		<xsl:variable name="string">
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="$chopString"/>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="substring($string, 1,1)='['">
			<xsl:value-of select="substring($string,2, string-length($string)-2)"/>
		</xsl:if>
		<xsl:if test="substring($string, 1,1)!='['">
			<xsl:value-of select="$string"/>
		</xsl:if>
	</xsl:template>
	<xsl:template name="rfcLanguages">
		<xsl:param name="nodeNum"/>
		<xsl:param name="usedLanguages"/>
		<xsl:param name="controlField008-35-37"/>
		<xsl:variable name="currentLanguage" select="."/>
		<xsl:choose>
			<xsl:when test="not($currentLanguage)"/>
			<xsl:when
				test="$currentLanguage!=$controlField008-35-37 and $currentLanguage!='rfc3066'">
				<xsl:if test="not(contains($usedLanguages,$currentLanguage))">
					<language>
						<xsl:if test="@code!='a'">
							<xsl:attribute name="objectPart">
								<xsl:choose>
									<xsl:when test="@code='b'">summary or subtitle</xsl:when>
									<xsl:when test="@code='d'">sung or spoken text</xsl:when>
									<xsl:when test="@code='e'">libretto</xsl:when>
									<xsl:when test="@code='f'">table of contents</xsl:when>
									<xsl:when test="@code='g'">accompanying material</xsl:when>
									<xsl:when test="@code='h'">translation</xsl:when>
								</xsl:choose>
							</xsl:attribute>
						</xsl:if>
						<languageTerm authority="rfc3066" type="code">
							<xsl:value-of select="$currentLanguage"/>
						</languageTerm>
					</language>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise> </xsl:otherwise>
		</xsl:choose>
	</xsl:template>

    <xsl:template name="datafield">
		<xsl:param name="tag"/>
		<xsl:param name="ind1">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="ind2">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="subfields"/>
		<xsl:element name="marc:datafield">
			<xsl:attribute name="tag">
				<xsl:value-of select="$tag"/>
			</xsl:attribute>
			<xsl:attribute name="ind1">
				<xsl:value-of select="$ind1"/>
			</xsl:attribute>
			<xsl:attribute name="ind2">
				<xsl:value-of select="$ind2"/>
			</xsl:attribute>
			<xsl:copy-of select="$subfields"/>
		</xsl:element>
	</xsl:template>

	<xsl:template name="subfieldSelect">
		<xsl:param name="codes">abcdefghijklmnopqrstuvwxyz</xsl:param>
		<xsl:param name="delimeter">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($codes, @code)">
					<xsl:value-of select="text()"/>
					<xsl:value-of select="$delimeter"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
	</xsl:template>

	<xsl:template name="buildSpaces">
		<xsl:param name="spaces"/>
		<xsl:param name="char">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:if test="$spaces>0">
			<xsl:value-of select="$char"/>
			<xsl:call-template name="buildSpaces">
				<xsl:with-param name="spaces" select="$spaces - 1"/>
				<xsl:with-param name="char" select="$char"/>
			</xsl:call-template>
		</xsl:if>
	</xsl:template>

	<xsl:template name="chopPunctuation">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/ </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationFront">
		<xsl:param name="chopString"/>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains('.:,;/[ ', substring($chopString,1,1))">
				<xsl:call-template name="chopPunctuationFront">
					<xsl:with-param name="chopString" select="substring($chopString,2,$length - 1)"
					/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationBack">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/] </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<!-- nate added 12/14/2007 for lccn.loc.gov: url encode ampersand, etc. -->
	<xsl:template name="url-encode">

		<xsl:param name="str"/>

		<xsl:if test="$str">
			<xsl:variable name="first-char" select="substring($str,1,1)"/>
			<xsl:choose>
				<xsl:when test="contains($safe,$first-char)">
					<xsl:value-of select="$first-char"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:variable name="codepoint">
						<xsl:choose>
							<xsl:when test="contains($ascii,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($ascii,$first-char)) + 32"
								/>
							</xsl:when>
							<xsl:when test="contains($latin1,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($latin1,$first-char)) + 160"/>
								<!-- was 160 -->
							</xsl:when>
							<xsl:otherwise>
								<xsl:message terminate="no">Warning: string contains a character
									that is out of range! Substituting "?".</xsl:message>
								<xsl:text>63</xsl:text>
							</xsl:otherwise>
						</xsl:choose>
					</xsl:variable>
					<xsl:variable name="hex-digit1"
						select="substring($hex,floor($codepoint div 16) + 1,1)"/>
					<xsl:variable name="hex-digit2" select="substring($hex,$codepoint mod 16 + 1,1)"/>
					<!-- <xsl:value-of select="concat('%',$hex-digit2)"/> -->
					<xsl:value-of select="concat('%',$hex-digit1,$hex-digit2)"/>
				</xsl:otherwise>
			</xsl:choose>
			<xsl:if test="string-length($str) &gt; 1">
				<xsl:call-template name="url-encode">
					<xsl:with-param name="str" select="substring($str,2)"/>
				</xsl:call-template>
			</xsl:if>
		</xsl:if>
	</xsl:template>
</xsl:stylesheet>$$ WHERE name = 'mods33';

ALTER TABLE actor.usr ALTER COLUMN juvenile SET NOT NULL;
ALTER TABLE actor.usr_address ALTER COLUMN pending SET NOT NULL;
ALTER TABLE config.circ_matrix_matchpoint ALTER COLUMN duration_rule SET NOT NULL;
ALTER TABLE config.circ_matrix_matchpoint ALTER COLUMN recurring_fine_rule SET NOT NULL;
ALTER TABLE config.circ_matrix_matchpoint ALTER COLUMN max_fine_rule SET NOT NULL;

-- We're updating the IDL, so flush cached mods slim records to avoid field mismatches
UPDATE metabib.metarecord SET mods = NULL;
UPDATE config.z3950_attr SET truncation = 1 WHERE source = 'loc';


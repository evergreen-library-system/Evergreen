/*
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 * Copyright (C) 2010  Equinox Software, Inc.
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

BEGIN;

INSERT INTO config.upgrade_log(version) VALUES ('1.6.0.4');

-- remove the metarecord link for "deleted" records
CREATE OR REPLACE RULE protect_bib_rec_delete AS ON DELETE TO biblio.record_entry DO INSTEAD (UPDATE biblio.record_entry SET deleted = TRUE WHERE OLD.id = biblio.record_entry.id; DELETE FROM metabib.metarecord_source_map WHERE source = OLD.id);

-- Match ingest fixes for leading / trailing whitespace on ISSNs and date ranges
UPDATE metabib.real_full_rec
    SET value = TRIM(value)
    WHERE (tag = '022' AND subfield = 'a')
        OR (tag = '100' AND subfield = 'd')
;

-- Correct reporter view definitions for ISSNs now that they contain spaces instead of hyphens
CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT	r.id,
	s.metarecord,
	r.fingerprint,
	r.quality,
	r.tcn_source,
	r.tcn_value,
	title.value AS title,
	uniform_title.value AS uniform_title,
	author.value AS author,
	publisher.value AS publisher,
	SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
	series_title.value AS series_title,
	series_statement.value AS series_statement,
	summary.value AS summary,
	ARRAY_ACCUM( SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
	ARRAY_ACCUM( DISTINCT SUBSTRING(REGEXP_REPLACE(issn.value, E'^\\s*(\\d{4})[-\\s](\\d{3,4}x?)\\s*', E'\\1 \\2') FROM 1 FOR 9)) AS issn,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
	ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM	biblio.record_entry r
	JOIN metabib.metarecord_source_map s ON (s.source = r.id)
	LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
	LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
	LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
	LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;


CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT	r.id,
	r.fingerprint,
	r.quality,
	r.tcn_source,
	r.tcn_value,
	title.value AS title,
	FIRST(author.value) AS author,
	publisher.value AS publisher,
	SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
	ARRAY_ACCUM( DISTINCT SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
	ARRAY_ACCUM( DISTINCT SUBSTRING(REGEXP_REPLACE(issn.value, E'^\\s*(\\d{4})[-\\s](\\d{3,4}x?)\\s*', E'\\1 \\2') FROM 1 FOR 9) ) AS issn
  FROM biblio.record_entry r
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,8,9;

-- Now rebuild the materialized simple record table that was built on reporter.old_super_simple_record
-- If you're using Slony, delete instead of truncate!

--DELETE FROM materialized.simple_record;
TRUNCATE TABLE reporter.materialized_simple_record;

INSERT INTO reporter.materialized_simple_record
    SELECT * FROM reporter.old_super_simple_record;

-- Replace the billable transaction summary view with one that is more cautious about NULL values
CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id,
		xact.usr,
		xact.xact_start,
		xact.xact_finish,
		COALESCE(credit.amount, 0.0::numeric) AS total_paid,
		credit.payment_ts AS last_payment_ts,
		credit.note AS last_payment_note,
		credit.payment_type AS last_payment_type,
		COALESCE(debit.amount, 0.0::numeric) AS total_owed,
		debit.billing_ts AS last_billing_ts,
		debit.note AS last_billing_note,
		debit.billing_type AS last_billing_type,
		COALESCE(debit.amount, 0.0::numeric) - COALESCE(credit.amount, 0.0::numeric) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
		JOIN pg_class p ON xact.tableoid = p.oid
		LEFT JOIN (
			SELECT	billing.xact,
				sum(billing.amount) AS amount,
				max(billing.billing_ts) AS billing_ts,
				last(billing.note) AS note,
				last(billing.billing_type) AS billing_type
			  FROM	money.billing
			  WHERE	billing.voided IS FALSE
			  GROUP BY billing.xact
			) debit ON xact.id = debit.xact
		LEFT JOIN (
			SELECT	payment_view.xact,
				sum(payment_view.amount) AS amount,
				max(payment_view.payment_ts) AS payment_ts,
				last(payment_view.note) AS note,
				last(payment_view.payment_type) AS payment_type
			  FROM	money.payment_view
			  WHERE	payment_view.voided IS FALSE
			  GROUP BY payment_view.xact
			) credit ON xact.id = credit.xact
	  ORDER BY debit.billing_ts, credit.payment_ts;

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

-- And rebuild the materialized view that was built on money.billable_xact_summary
TRUNCATE TABLE money.materialized_billable_xact_summary;
INSERT INTO money.materialized_billable_xact_summary
	SELECT * FROM money.billable_xact_summary;

-- Updated in-db circ and functions which return a matchpoint whenever possible, for override
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

    -- Fail if we couldn't find the user 
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, match_item, match_user, renewal);
    result.matchpoint := circ_test.id;

    -- Fail if we couldn't find a matchpoint
    IF result.matchpoint IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate
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

    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( circ_test.org_unit );

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
               AND circ.circ_lib IN ( SELECT * FROM explode_array(context_org_list) )
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

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS $func$
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

    result.success := TRUE;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
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
    result.matchpoint := matchpoint_id;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

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
		   AND (upm.perm = n_perm OR upm.perm = -1)
       				UNION
		SELECT	gpm.depth
		  FROM	permission.grp_perm_map gpm
		  WHERE	(gpm.perm = n_perm OR gpm.perm = -1)
	        AND gpm.grp IN (
	 		   SELECT	(permission.grp_ancestors(
					(SELECT profile FROM actor.usr WHERE id = user_id)
				)).id
			)
       				UNION
		SELECT	p.depth
		  FROM	permission.grp_perm_map p 
		  WHERE (p.perm = n_perm OR p.perm = -1)
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


COMMIT;

-- Ability to import a record with a different TCN
INSERT INTO permission.perm_list (code, description) VALUES ('ALLOW_ALT_TCN', 'Allows staff to import a record using an alternate TCN to avoid conflicts');

-- Ability to merge users
INSERT INTO permission.perm_list (code, description) VALUES ('MERGE_USERS', 'Allows user records to be merged');

-- More trigger event definition permissions
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_EVENT_DEF', 'Allow a user to administer trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_CLEANUP', 'Allow a user to create, delete, and update trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_CLEANUP', 'Allow a user to create trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_CLEANUP', 'Allow a user to delete trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_CLEANUP', 'Allow a user to update trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_EVENT_DEF', 'Allow a user to create trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_EVENT_DEF', 'Allow a user to delete trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_EVENT_DEF', 'Allow a user to update trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_TRIGGER_EVENT_DEF', 'Allow a user to view trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_HOOK', 'Allow a user to create, update, and delete trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_HOOK', 'Allow a user to create trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_HOOK', 'Allow a user to delete trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_HOOK', 'Allow a user to update trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_REACTOR', 'Allow a user to create, update, and delete trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_REACTOR', 'Allow a user to create trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_REACTOR', 'Allow a user to delete trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_REACTOR', 'Allow a user to update trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_TEMPLATE_OUTPUT', 'Allow a user to delete trigger template output');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_TEMPLATE_OUTPUT', 'Allow a user to delete trigger template output');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_VALIDATOR', 'Allow a user to create, update, and delete trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_VALIDATOR', 'Allow a user to create trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_VALIDATOR', 'Allow a user to delete trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_VALIDATOR', 'Allow a user to update trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_ORG_UNIT_SETTING.circ.block_renews_for_holds','Allow a user to enable blocking of renews on items that could fulfill holds');


-- Add trigger administration permissions to the Local System Administrator group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 1, false FROM permission.perm_list
        WHERE code LIKE 'ADMIN_TRIGGER%'
            OR code LIKE 'CREATE_TRIGGER%'
            OR code LIKE 'DELETE_TRIGGER%'
            OR code LIKE 'UPDATE_TRIGGER%'
;
-- View trigger permissions are required at a consortial level for initial setup
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 0, false FROM permission.perm_list WHERE code LIKE 'VIEW_TRIGGER%';


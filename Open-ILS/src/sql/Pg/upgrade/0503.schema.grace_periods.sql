BEGIN;

-- FAIR WARNING:
-- Using a tool such as pgadmin to run this script may fail
-- If it does, try psql command line.

-- Change this to FALSE to disable updating existing circs
-- Otherwise will use the fine interval for the grace period
\set CircGrace TRUE

INSERT INTO config.upgrade_log (version) VALUES ('0503');

-- New Columns

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN grace_period INTERVAL;

ALTER TABLE config.rule_recurring_fine
    ADD COLUMN grace_period INTERVAL NOT NULL DEFAULT '1 day';

ALTER TABLE action.circulation
    ADD COLUMN grace_period INTERVAL NOT NULL DEFAULT '0 seconds';

ALTER TABLE action.aged_circulation
    ADD COLUMN grace_period INTERVAL NOT NULL DEFAULT '0 seconds';

-- Remove defaults needed to stop null complaints

ALTER TABLE action.circulation
    ALTER COLUMN grace_period DROP DEFAULT;

ALTER TABLE action.aged_circulation
    ALTER COLUMN grace_period DROP DEFAULT;

-- Drop Views

DROP VIEW action.all_circulation;
DROP VIEW action.open_circulation;
DROP VIEW action.billable_circulations;

-- Replace Views

CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, cp.location AS copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = a.id);

CREATE OR REPLACE VIEW action.open_circulation AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	checkin_time IS NULL
	  ORDER BY due_date;
		

CREATE OR REPLACE VIEW action.billable_circulations AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	xact_finish IS NULL;

-- Drop Functions that rely on types

DROP FUNCTION action.item_user_circ_test(INT, BIGINT, INT, BOOL);
DROP FUNCTION action.item_user_circ_test(INT, BIGINT, INT);
DROP FUNCTION action.item_user_renew_test(INT, BIGINT, INT);

-- Drop Types that are changing

DROP TYPE action.circ_matrix_test_result;

-- Replace Types

CREATE TYPE action.circ_matrix_test_result AS ( success BOOL, fail_part TEXT, buildrows INT[], matchpoint INT, circulate BOOL, duration_rule INT, recurring_fine_rule INT, max_fine_rule INT, hard_due_date INT, renewals INT, grace_period INTERVAL );

-- Fix/Replace Functions

CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, item_object asset.copy, user_object actor.usr, renewal BOOL ) RETURNS action.found_circ_matrix_matchpoint AS $func$
DECLARE
    cn_object       asset.call_number%ROWTYPE;
    rec_descriptor  metabib.rec_descriptor%ROWTYPE;
    cur_matchpoint  config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint      config.circ_matrix_matchpoint%ROWTYPE;
    weights         config.circ_matrix_weights%ROWTYPE;
    user_age        INTERVAL;
    denominator     NUMERIC(6,2);
    row_list        INT[];
    result          action.found_circ_matrix_matchpoint;
BEGIN
    -- Assume failure
    result.success = false;

    -- Fetch useful data
    SELECT INTO cn_object       * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor  * FROM metabib.rec_descriptor   WHERE record = cn_object.record;

    -- Pre-generate this so we only calc it once
    IF user_object.dob IS NOT NULL THEN
        SELECT INTO user_age age(user_object.dob);
    END IF;

    -- Grab the closest set circ weight setting.
    SELECT INTO weights cw.*
      FROM config.weight_assoc wa
           JOIN config.circ_matrix_weights cw ON (cw.id = wa.circ_weights)
           JOIN actor.org_unit_ancestors_distance( context_ou ) d ON (wa.org_unit = d.id)
      WHERE active
      ORDER BY d.distance
      LIMIT 1;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.grp                 := 11.0;
        weights.org_unit            := 10.0;
        weights.circ_modifier       := 5.0;
        weights.marc_type           := 4.0;
        weights.marc_form           := 3.0;
        weights.marc_vr_format      := 2.0;
        weights.copy_circ_lib       := 8.0;
        weights.copy_owning_lib     := 8.0;
        weights.user_home_ou        := 8.0;
        weights.ref_flag            := 1.0;
        weights.juvenile_flag       := 6.0;
        weights.is_renewal          := 7.0;
        weights.usr_age_lower_bound := 0.0;
        weights.usr_age_upper_bound := 0.0;
    END IF;

    -- Determine the max (expected) depth (+1) of the org tree and max depth of the permisson tree
    -- If you break your org tree with funky parenting this may be wrong
    -- Note: This CTE is duplicated in the find_hold_matrix_matchpoint function, and it may be a good idea to split it off to a function
    -- We use one denominator for all tree-based checks for when permission groups and org units have the same weighting
    WITH all_distance(distance) AS (
            SELECT depth AS distance FROM actor.org_unit_type
        UNION
       	    SELECT distance AS distance FROM permission.grp_ancestors_distance((SELECT id FROM permission.grp_tree WHERE parent IS NULL))
	)
    SELECT INTO denominator MAX(distance) + 1 FROM all_distance;

    -- Loop over all the potential matchpoints
    FOR cur_matchpoint IN
        SELECT m.*
          FROM  config.circ_matrix_matchpoint m
                /*LEFT*/ JOIN permission.grp_ancestors_distance( user_object.profile ) upgad ON m.grp = upgad.id
                /*LEFT*/ JOIN actor.org_unit_ancestors_distance( context_ou ) ctoua ON m.org_unit = ctoua.id
                LEFT JOIN actor.org_unit_ancestors_distance( cn_object.owning_lib ) cnoua ON m.copy_owning_lib = cnoua.id
                LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.copy_circ_lib = iooua.id
                LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
          WHERE m.active
                -- Permission Groups
             -- AND (m.grp                      IS NULL OR upgad.id IS NOT NULL) -- Optional Permission Group?
                -- Org Units
             -- AND (m.org_unit                 IS NULL OR ctoua.id IS NOT NULL) -- Optional Org Unit?
                AND (m.copy_owning_lib          IS NULL OR cnoua.id IS NOT NULL)
                AND (m.copy_circ_lib            IS NULL OR iooua.id IS NOT NULL)
                AND (m.user_home_ou             IS NULL OR uhoua.id IS NOT NULL)
                -- Circ Type
                AND (m.is_renewal               IS NULL OR m.is_renewal = renewal)
                -- Static User Checks
                AND (m.juvenile_flag            IS NULL OR m.juvenile_flag = user_object.juvenile)
                AND (m.usr_age_lower_bound      IS NULL OR (user_age IS NOT NULL AND m.usr_age_lower_bound < user_age))
                AND (m.usr_age_upper_bound      IS NULL OR (user_age IS NOT NULL AND m.usr_age_upper_bound > user_age))
                -- Static Item Checks
                AND (m.circ_modifier            IS NULL OR m.circ_modifier = item_object.circ_modifier)
                AND (m.marc_type                IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
                AND (m.marc_form                IS NULL OR m.marc_form = rec_descriptor.item_form)
                AND (m.marc_vr_format           IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
                AND (m.ref_flag                 IS NULL OR m.ref_flag = item_object.ref)
          ORDER BY
                -- Permission Groups
                CASE WHEN upgad.distance        IS NOT NULL THEN 2^(2*weights.grp - (upgad.distance/denominator)) ELSE 0.0 END +
                -- Org Units
                CASE WHEN ctoua.distance        IS NOT NULL THEN 2^(2*weights.org_unit - (ctoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN cnoua.distance        IS NOT NULL THEN 2^(2*weights.copy_owning_lib - (cnoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN iooua.distance        IS NOT NULL THEN 2^(2*weights.copy_circ_lib - (iooua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN uhoua.distance        IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
                -- Circ Type                    -- Note: 4^x is equiv to 2^(2*x)
                CASE WHEN m.is_renewal          IS NOT NULL THEN 4^weights.is_renewal ELSE 0.0 END +
                -- Static User Checks
                CASE WHEN m.juvenile_flag       IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
                CASE WHEN m.usr_age_lower_bound IS NOT NULL THEN 4^weights.usr_age_lower_bound ELSE 0.0 END +
                CASE WHEN m.usr_age_upper_bound IS NOT NULL THEN 4^weights.usr_age_upper_bound ELSE 0.0 END +
                -- Static Item Checks
                CASE WHEN m.circ_modifier       IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
                CASE WHEN m.marc_type           IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
                CASE WHEN m.marc_form           IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
                CASE WHEN m.marc_vr_format      IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
                CASE WHEN m.ref_flag            IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END DESC,
                -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
                -- This prevents "we changed the table order by updating a rule, and we started getting different results"
                m.id LOOP

        -- Record the full matching row list
        row_list := row_list || cur_matchpoint.id;

        -- No matchpoint yet?
        IF matchpoint.id IS NULL THEN
            -- Take the entire matchpoint as a starting point
            matchpoint := cur_matchpoint;
            CONTINUE; -- No need to look at this row any more.
        END IF;

        -- Incomplete matchpoint?
        IF matchpoint.circulate IS NULL THEN
            matchpoint.circulate := cur_matchpoint.circulate;
        END IF;
        IF matchpoint.duration_rule IS NULL THEN
            matchpoint.duration_rule := cur_matchpoint.duration_rule;
        END IF;
        IF matchpoint.recurring_fine_rule IS NULL THEN
            matchpoint.recurring_fine_rule := cur_matchpoint.recurring_fine_rule;
        END IF;
        IF matchpoint.max_fine_rule IS NULL THEN
            matchpoint.max_fine_rule := cur_matchpoint.max_fine_rule;
        END IF;
        IF matchpoint.hard_due_date IS NULL THEN
            matchpoint.hard_due_date := cur_matchpoint.hard_due_date;
        END IF;
        IF matchpoint.total_copy_hold_ratio IS NULL THEN
            matchpoint.total_copy_hold_ratio := cur_matchpoint.total_copy_hold_ratio;
        END IF;
        IF matchpoint.available_copy_hold_ratio IS NULL THEN
            matchpoint.available_copy_hold_ratio := cur_matchpoint.available_copy_hold_ratio;
        END IF;
        IF matchpoint.renewals IS NULL THEN
            matchpoint.renewals := cur_matchpoint.renewals;
        END IF;
        IF matchpoint.grace_period IS NULL THEN
            matchpoint.grace_period := cur_matchpoint.grace_period;
        END IF;
    END LOOP;

    -- Check required fields
    IF matchpoint.circulate             IS NOT NULL AND
       matchpoint.duration_rule         IS NOT NULL AND
       matchpoint.recurring_fine_rule   IS NOT NULL AND
       matchpoint.max_fine_rule         IS NOT NULL THEN
        -- All there? We have a completed match.
        result.success := true;
    END IF;

    -- Include the assembled matchpoint, even if it isn't complete
    result.matchpoint := matchpoint;

    -- Include (for debugging) the full list of matching rows
    result.buildrows := row_list;

    -- Hand the result back to caller
    RETURN result;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.circ_matrix_test_result AS $func$
DECLARE
    user_object             actor.usr%ROWTYPE;
    standing_penalty        config.standing_penalty%ROWTYPE;
    item_object             asset.copy%ROWTYPE;
    item_status_object      config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result                  action.circ_matrix_test_result;
    circ_test               action.found_circ_matrix_matchpoint;
    circ_matchpoint         config.circ_matrix_matchpoint%ROWTYPE;
    out_by_circ_mod         config.circ_matrix_circ_mod_test%ROWTYPE;
    circ_mod_map            config.circ_matrix_circ_mod_test_map%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
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
        result.fail_part := 'no_item';
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

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, item_object, user_object, renewal);

    circ_matchpoint             := circ_test.matchpoint;
    result.matchpoint           := circ_matchpoint.id;
    result.circulate            := circ_matchpoint.circulate;
    result.duration_rule        := circ_matchpoint.duration_rule;
    result.recurring_fine_rule  := circ_matchpoint.recurring_fine_rule;
    result.max_fine_rule        := circ_matchpoint.max_fine_rule;
    result.hard_due_date        := circ_matchpoint.hard_due_date;
    result.renewals             := circ_matchpoint.renewals;
    result.grace_period         := circ_matchpoint.grace_period;
    result.buildrows            := circ_test.buildrows;

    -- Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN; -- All tests after this point require a matchpoint. No sense in running on an incomplete or missing one.
    END IF;

    -- Apparently....use the circ matchpoint org unit to determine what org units are valid.
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( circ_matchpoint.org_unit );

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
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE penalty_type LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the test is set to hard non-circulating
    IF circ_matchpoint.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the total copy-hold ratio is too low
    IF circ_matchpoint.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_matchpoint.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_matchpoint.available_copy_hold_ratio IS NOT NULL THEN
        IF hold_ratio.hold_count IS NULL THEN
            SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        END IF;
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_matchpoint.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the user has too many items with specific circ_modifiers checked out
    FOR out_by_circ_mod IN SELECT * FROM config.circ_matrix_circ_mod_test WHERE matchpoint = circ_matchpoint.id LOOP
        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
            JOIN asset.copy cp ON (cp.id = circ.target_copy)
          WHERE circ.usr = match_user
               AND circ.circ_lib IN ( SELECT * FROM unnest(context_org_list) )
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

CREATE OR REPLACE FUNCTION action.item_user_circ_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, FALSE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.item_user_renew_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, TRUE );
$func$ LANGUAGE SQL;

-- Update recurring fine rules
UPDATE config.rule_recurring_fine SET grace_period=recurrence_interval;

-- Update Circulation Data
-- Only update if we were told to and the circ hasn't been checked in
UPDATE action.circulation SET grace_period=fine_interval WHERE :CircGrace AND (checkin_time IS NULL);

COMMIT;

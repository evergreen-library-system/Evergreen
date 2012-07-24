BEGIN;

SELECT evergreen.upgrade_deps_block_check('0720', :eg_version);

ALTER TABLE config.circ_matrix_weights 
    ADD COLUMN copy_location NUMERIC(6,2) NOT NULL DEFAULT 5.0;
UPDATE config.circ_matrix_weights 
    SET copy_location = 0.0 WHERE name = 'All_Equal';
ALTER TABLE config.circ_matrix_weights 
    ALTER COLUMN copy_location DROP DEFAULT; -- for consistency w/ baseline schema

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN copy_location INTEGER REFERENCES asset.copy_location (id) DEFERRABLE INITIALLY DEFERRED;

DROP INDEX config.ccmm_once_per_paramset;

CREATE UNIQUE INDEX ccmm_once_per_paramset ON config.circ_matrix_matchpoint (org_unit, grp, COALESCE(circ_modifier, ''), COALESCE(copy_location::TEXT, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level,''), COALESCE(marc_vr_format, ''), COALESCE(copy_circ_lib::TEXT, ''), COALESCE(copy_owning_lib::TEXT, ''), COALESCE(user_home_ou::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(is_renewal::TEXT, ''), COALESCE(usr_age_lower_bound::TEXT, ''), COALESCE(usr_age_upper_bound::TEXT, ''), COALESCE(item_age::TEXT, '')) WHERE active;

-- Linkage between limit sets and circ mods
CREATE TABLE config.circ_limit_set_copy_loc_map (
    id          SERIAL  PRIMARY KEY,
    limit_set   INT     NOT NULL REFERENCES config.circ_limit_set (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    copy_loc    INT     NOT NULL REFERENCES asset.copy_location (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT cl_once_per_set UNIQUE (limit_set, copy_loc)
);

-- Add support for checking config.circ_limit_set_copy_loc_map's
CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) 
    RETURNS SETOF action.circ_matrix_test_result AS $func$
DECLARE
    user_object             actor.usr%ROWTYPE;
    standing_penalty        config.standing_penalty%ROWTYPE;
    item_object             asset.copy%ROWTYPE;
    item_status_object      config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result                  action.circ_matrix_test_result;
    circ_test               action.found_circ_matrix_matchpoint;
    circ_matchpoint         config.circ_matrix_matchpoint%ROWTYPE;
    circ_limit_set          config.circ_limit_set%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
    result.success := TRUE;

    -- Need user info to look up matchpoints
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user AND NOT deleted;

    -- (Insta)Fail if we couldn't find the user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Need item info to look up matchpoints
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item AND NOT deleted;

    -- (Insta)Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
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

    -- (Insta)Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- All failures before this point are non-recoverable
    -- Below this point are possibly overridable failures

    -- Fail if the user is barred
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
    -- Alternately, fail if the item isn't checked out on a renewal
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

    -- Use Circ OU for penalties and such
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( circ_ou );

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

    -- Fail if the user has too many items out by defined limit sets
    FOR circ_limit_set IN SELECT ccls.* FROM config.circ_limit_set ccls
      JOIN config.circ_matrix_limit_set_map ccmlsm ON ccmlsm.limit_set = ccls.id
      WHERE ccmlsm.active AND ( ccmlsm.matchpoint = circ_matchpoint.id OR
        ( ccmlsm.matchpoint IN (SELECT * FROM unnest(result.buildrows)) AND ccmlsm.fallthrough )
        ) LOOP
            IF circ_limit_set.items_out > 0 AND NOT renewal THEN
                SELECT INTO context_org_list ARRAY_AGG(aou.id)
                  FROM actor.org_unit_full_path( circ_ou ) aou
                    JOIN actor.org_unit_type aout ON aou.ou_type = aout.id
                  WHERE aout.depth >= circ_limit_set.depth;
                IF circ_limit_set.global THEN
                    WITH RECURSIVE descendant_depth AS (
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                        WHERE ou.id IN (SELECT * FROM unnest(context_org_list))
                            UNION
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                            JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
                    ) SELECT INTO context_org_list ARRAY_AGG(ou.id) FROM actor.org_unit ou JOIN descendant_depth USING (id);
                END IF;
                SELECT INTO items_out COUNT(DISTINCT circ.id)
                  FROM action.circulation circ
                    JOIN asset.copy copy ON (copy.id = circ.target_copy)
                    LEFT JOIN action.circulation_limit_group_map aclgm ON (circ.id = aclgm.circ)
                  WHERE circ.usr = match_user
                    AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                    AND circ.checkin_time IS NULL
                    AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
                    AND (copy.circ_modifier IN (SELECT circ_mod FROM config.circ_limit_set_circ_mod_map WHERE limit_set = circ_limit_set.id)
                        OR copy.location IN (SELECT copy_loc FROM config.circ_limit_set_copy_loc_map WHERE limit_set = circ_limit_set.id)
                        OR aclgm.limit_group IN (SELECT limit_group FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id)
                    );
                IF items_out >= circ_limit_set.items_out THEN
                    result.fail_part := 'config.circ_matrix_circ_mod_test';
                    result.success := FALSE;
                    done := TRUE;
                    RETURN NEXT result;
                END IF;
            END IF;
            SELECT INTO result.limit_groups result.limit_groups || ARRAY_AGG(limit_group) FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id AND NOT check_only;
    END LOOP;

    -- If we passed everything, return the successful matchpoint
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


-- adding copy_loc to circ_matrix_matchpoint
CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, item_object asset.copy, user_object actor.usr, renewal BOOL ) RETURNS action.found_circ_matrix_matchpoint AS $func$
DECLARE
    cn_object       asset.call_number%ROWTYPE;
    rec_descriptor  metabib.rec_descriptor%ROWTYPE;
    cur_matchpoint  config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint      config.circ_matrix_matchpoint%ROWTYPE;
    weights         config.circ_matrix_weights%ROWTYPE;
    user_age        INTERVAL;
    my_item_age     INTERVAL;
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

    -- Ditto
    SELECT INTO my_item_age age(coalesce(item_object.active_date, now()));

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
        weights.copy_location       := 5.0;
        weights.marc_type           := 4.0;
        weights.marc_form           := 3.0;
        weights.marc_bib_level      := 2.0;
        weights.marc_vr_format      := 2.0;
        weights.copy_circ_lib       := 8.0;
        weights.copy_owning_lib     := 8.0;
        weights.user_home_ou        := 8.0;
        weights.ref_flag            := 1.0;
        weights.juvenile_flag       := 6.0;
        weights.is_renewal          := 7.0;
        weights.usr_age_lower_bound := 0.0;
        weights.usr_age_upper_bound := 0.0;
        weights.item_age            := 0.0;
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
                AND (m.copy_location            IS NULL OR m.copy_location = item_object.location)
                AND (m.marc_type                IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
                AND (m.marc_form                IS NULL OR m.marc_form = rec_descriptor.item_form)
                AND (m.marc_bib_level           IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
                AND (m.marc_vr_format           IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
                AND (m.ref_flag                 IS NULL OR m.ref_flag = item_object.ref)
                AND (m.item_age                 IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
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
                CASE WHEN m.copy_location       IS NOT NULL THEN 4^weights.copy_location ELSE 0.0 END +
                CASE WHEN m.marc_type           IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
                CASE WHEN m.marc_form           IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
                CASE WHEN m.marc_vr_format      IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
                CASE WHEN m.ref_flag            IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END +
                -- Item age has a slight adjustment to weight based on value.
                -- This should ensure that a shorter age limit comes first when all else is equal.
                -- NOTE: This assumes that intervals will normally be in days.
                CASE WHEN m.item_age            IS NOT NULL THEN 4^weights.item_age - 1 + 86400/EXTRACT(EPOCH FROM m.item_age) ELSE 0.0 END DESC,
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

COMMIT;


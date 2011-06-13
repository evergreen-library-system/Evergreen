ALTER TABLE asset.copy
    ADD COLUMN active_date TIMESTAMP WITH TIME ZONE;

ALTER TABLE auditor.asset_copy_history
    ADD COLUMN active_date TIMESTAMP WITH TIME ZONE;

ALTER TABLE config.copy_status
    ADD COLUMN copy_active BOOL NOT NULL DEFAULT FALSE;

ALTER TABLE config.circ_matrix_weights
    ADD COLUMN item_age NUMERIC(6,2) NOT NULL DEFAULT 0.0;

ALTER TABLE config.hold_matrix_weights
    ADD COLUMN item_age NUMERIC(6,2) NOT NULL DEFAULT 0.0;

-- The two defaults above were to stop erroring on NOT NULL
-- Remove them here
ALTER TABLE config.circ_matrix_weights
    ALTER COLUMN item_age DROP DEFAULT;

ALTER TABLE config.hold_matrix_weights
    ALTER COLUMN item_age DROP DEFAULT;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN item_age INTERVAL;

ALTER TABLE config.hold_matrix_matchpoint
    ADD COLUMN item_age INTERVAL;

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> OLD.status THEN
        NEW.status_changed_time := now();
        IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
            NEW.active_date := now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION asset.acp_created()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
        NEW.active_date := now();
    END IF;
    IF NEW.status_changed_time IS NULL THEN
        NEW.status_changed_time := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_created_trig
    BEFORE INSERT ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_created();

CREATE TRIGGER sunit_created_trig
    BEFORE INSERT ON serial.unit
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_created();

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object     asset.call_number%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
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

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
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

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
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
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_cn_object.owning_lib);
        ELSE
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_object.circ_lib);
        END IF;
        IF use_active_date = 'true' THEN
            age_protect_date := COALESCE(item_object.active_date, NOW());
        ELSE
            age_protect_date := item_object.create_date;
        END IF;
        IF age_protect_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
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
    IF item_object.active_date IS NOT NULL THEN
        SELECT INTO my_item_age age(item_object.active_date);
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

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint(pickup_ou integer, request_ou integer, match_item bigint, match_user integer, match_requestor integer)
  RETURNS integer AS
$func$
DECLARE
    requestor_object    actor.usr%ROWTYPE;
    user_object         actor.usr%ROWTYPE;
    item_object         asset.copy%ROWTYPE;
    item_cn_object      asset.call_number%ROWTYPE;
    my_item_age         INTERVAL;
    rec_descriptor      metabib.rec_descriptor%ROWTYPE;
    matchpoint          config.hold_matrix_matchpoint%ROWTYPE;
    weights             config.hold_matrix_weights%ROWTYPE;
    denominator         NUMERIC(6,2);
BEGIN
    SELECT INTO user_object         * FROM actor.usr                WHERE id = match_user;
    SELECT INTO requestor_object    * FROM actor.usr                WHERE id = match_requestor;
    SELECT INTO item_object         * FROM asset.copy               WHERE id = match_item;
    SELECT INTO item_cn_object      * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor      * FROM metabib.rec_descriptor   WHERE record = item_cn_object.record;

    IF item_object.active_date IS NOT NULL THEN
        SELECT INTO my_item_age age(item_object.active_date);
    END IF;

    -- The item's owner should probably be the one determining if the item is holdable
    -- How to decide that is debatable. Decided to default to the circ library (where the item lives)
    -- This flag will allow for setting it to the owning library (where the call number "lives")
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.weight_owner_not_circ' AND enabled;

    -- Grab the closest set circ weight setting.
    IF NOT FOUND THEN
        -- Default to circ library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    ELSE
        -- Flag is set, use owning library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    END IF;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.user_home_ou    := 5.0;
        weights.request_ou      := 5.0;
        weights.pickup_ou       := 5.0;
        weights.item_owning_ou  := 5.0;
        weights.item_circ_ou    := 5.0;
        weights.usr_grp         := 7.0;
        weights.requestor_grp   := 8.0;
        weights.circ_modifier   := 4.0;
        weights.marc_type       := 3.0;
        weights.marc_form       := 2.0;
        weights.marc_bib_level  := 1.0;
        weights.marc_vr_format  := 1.0;
        weights.juvenile_flag   := 4.0;
        weights.ref_flag        := 0.0;
        weights.item_age        := 0.0;
    END IF;

    -- Determine the max (expected) depth (+1) of the org tree and max depth of the permisson tree
    -- If you break your org tree with funky parenting this may be wrong
    -- Note: This CTE is duplicated in the find_circ_matrix_matchpoint function, and it may be a good idea to split it off to a function
    -- We use one denominator for all tree-based checks for when permission groups and org units have the same weighting
    WITH all_distance(distance) AS (
            SELECT depth AS distance FROM actor.org_unit_type
        UNION
            SELECT distance AS distance FROM permission.grp_ancestors_distance((SELECT id FROM permission.grp_tree WHERE parent IS NULL))
	)
    SELECT INTO denominator MAX(distance) + 1 FROM all_distance;

    -- To ATTEMPT to make this work like it used to, make it reverse the user/requestor profile ids.
    -- This may be better implemented as part of the upgrade script?
    -- Set usr_grp = requestor_grp, requestor_grp = 1 or something when this flag is already set
    -- Then remove this flag, of course.
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.usr_not_requestor' AND enabled;

    IF FOUND THEN
        -- Note: This, to me, is REALLY hacky. I put it in anyway.
        -- If you can't tell, this is a single call swap on two variables.
        SELECT INTO user_object.profile, requestor_object.profile
                    requestor_object.profile, user_object.profile;
    END IF;

    -- Select the winning matchpoint into the matchpoint variable for returning
    SELECT INTO matchpoint m.*
      FROM  config.hold_matrix_matchpoint m
            /*LEFT*/ JOIN permission.grp_ancestors_distance( requestor_object.profile ) rpgad ON m.requestor_grp = rpgad.id
            LEFT JOIN permission.grp_ancestors_distance( user_object.profile ) upgad ON m.usr_grp = upgad.id
            LEFT JOIN actor.org_unit_ancestors_distance( pickup_ou ) puoua ON m.pickup_ou = puoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( request_ou ) rqoua ON m.request_ou = rqoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) cnoua ON m.item_owning_ou = cnoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.item_circ_ou = iooua.id
            LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
      WHERE m.active
            -- Permission Groups
         -- AND (m.requestor_grp        IS NULL OR upgad.id IS NOT NULL) -- Optional Requestor Group?
            AND (m.usr_grp              IS NULL OR upgad.id IS NOT NULL)
            -- Org Units
            AND (m.pickup_ou            IS NULL OR (puoua.id IS NOT NULL AND (puoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.request_ou           IS NULL OR (rqoua.id IS NOT NULL AND (rqoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_owning_ou       IS NULL OR (cnoua.id IS NOT NULL AND (cnoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_circ_ou         IS NULL OR (iooua.id IS NOT NULL AND (iooua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.user_home_ou         IS NULL OR (uhoua.id IS NOT NULL AND (uhoua.distance = 0 OR NOT m.strict_ou_match)))
            -- Static User Checks
            AND (m.juvenile_flag        IS NULL OR m.juvenile_flag = user_object.juvenile)
            -- Static Item Checks
            AND (m.circ_modifier        IS NULL OR m.circ_modifier = item_object.circ_modifier)
            AND (m.marc_type            IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
            AND (m.marc_form            IS NULL OR m.marc_form = rec_descriptor.item_form)
            AND (m.marc_bib_level       IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
            AND (m.marc_vr_format       IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
            AND (m.ref_flag             IS NULL OR m.ref_flag = item_object.ref)
            AND (m.item_age             IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
      ORDER BY
            -- Permission Groups
            CASE WHEN rpgad.distance    IS NOT NULL THEN 2^(2*weights.requestor_grp - (rpgad.distance/denominator)) ELSE 0.0 END +
            CASE WHEN upgad.distance    IS NOT NULL THEN 2^(2*weights.usr_grp - (upgad.distance/denominator)) ELSE 0.0 END +
            -- Org Units
            CASE WHEN puoua.distance    IS NOT NULL THEN 2^(2*weights.pickup_ou - (puoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN rqoua.distance    IS NOT NULL THEN 2^(2*weights.request_ou - (rqoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN cnoua.distance    IS NOT NULL THEN 2^(2*weights.item_owning_ou - (cnoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN iooua.distance    IS NOT NULL THEN 2^(2*weights.item_circ_ou - (iooua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN uhoua.distance    IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
            -- Static User Checks       -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.juvenile_flag   IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier   IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
            CASE WHEN m.marc_type       IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
            CASE WHEN m.marc_form       IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
            CASE WHEN m.marc_vr_format  IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
            CASE WHEN m.ref_flag        IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END +
            -- Item age has a slight adjustment to weight based on value.
            -- This should ensure that a shorter age limit comes first when all else is equal.
            -- NOTE: This assumes that intervals will normally be in days.
            CASE WHEN m.item_age            IS NOT NULL THEN 4^weights.item_age - 86400/EXTRACT(EPOCH FROM m.item_age) ELSE 0.0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return just the ID for now
    RETURN matchpoint.id;
END;
$func$ LANGUAGE 'plpgsql';

DROP INDEX IF EXISTS config.ccmm_once_per_paramset;

DROP INDEX IF EXISTS config.chmm_once_per_paramset;

CREATE UNIQUE INDEX ccmm_once_per_paramset ON config.circ_matrix_matchpoint (org_unit, grp, COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level,''), COALESCE(marc_vr_format, ''), COALESCE(copy_circ_lib::TEXT, ''), COALESCE(copy_owning_lib::TEXT, ''), COALESCE(user_home_ou::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(is_renewal::TEXT, ''), COALESCE(usr_age_lower_bound::TEXT, ''), COALESCE(usr_age_upper_bound::TEXT, ''), COALESCE(item_age::TEXT, '')) WHERE active;

CREATE UNIQUE INDEX chmm_once_per_paramset ON config.hold_matrix_matchpoint (COALESCE(user_home_ou::TEXT, ''), COALESCE(request_ou::TEXT, ''), COALESCE(pickup_ou::TEXT, ''), COALESCE(item_owning_ou::TEXT, ''), COALESCE(item_circ_ou::TEXT, ''), COALESCE(usr_grp::TEXT, ''), COALESCE(requestor_grp::TEXT, ''), COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level, ''), COALESCE(marc_vr_format, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(item_age::TEXT, '')) WHERE active;

UPDATE config.copy_status SET copy_active = true WHERE id IN (0, 1, 7, 8, 10, 12, 15);

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'circ.holds.age_protect.active_date', 'Holds: Use Active Date for Age Protection', 'When calculating age protection rules use the active date instead of the creation date.', 'bool');

-- Assume create date when item is in status we would update active date for anyway
UPDATE asset.copy SET active_date = create_date WHERE status IN (SELECT id FROM config.copy_status WHERE copy_active = true);

-- Assume create date for any item with circs
UPDATE asset.copy SET active_date = create_date WHERE id IN (SELECT id FROM extend_reporter.full_circ_count WHERE circ_count > 0);

-- Assume create date for status change time while we are at it. Because being created WAS a change in status.
UPDATE asset.copy SET status_changed_time = create_date WHERE status_changed_time IS NULL;

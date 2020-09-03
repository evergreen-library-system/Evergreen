BEGIN;

SELECT evergreen.upgrade_deps_block_check('1221', :eg_version);

CREATE OR REPLACE FUNCTION action.copy_calculated_proximity(
    pickup  INT,
    request INT,
    vacp_cl  INT,
    vacp_cm  TEXT,
    vacn_ol  INT,
    vacl_ol  INT
) RETURNS NUMERIC AS $f$
DECLARE
    baseline_prox   NUMERIC;
    aoupa           actor.org_unit_proximity_adjustment%ROWTYPE;
BEGIN

    -- First, gather the baseline proximity of "here" to pickup lib
    SELECT prox INTO baseline_prox FROM actor.org_unit_proximity WHERE from_org = vacp_cl AND to_org = pickup;

    -- Find any absolute adjustments, and set the baseline prox to that
    SELECT  adj.* INTO aoupa
      FROM  actor.org_unit_proximity_adjustment adj
            LEFT JOIN actor.org_unit_ancestors_distance(vacp_cl) acp_cl ON (acp_cl.id = adj.item_circ_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(vacn_ol) acn_ol ON (acn_ol.id = adj.item_owning_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(vacl_ol) acl_ol ON (acl_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(pickup) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(request) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = vacp_cm) AND
            (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
            (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
            (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
            (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
            (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
            absolute_adjustment AND
            COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
      ORDER BY
            COALESCE(acp_cl.distance,999)
                + COALESCE(acn_ol.distance,999)
                + COALESCE(acl_ol.distance,999)
                + COALESCE(ahr_pl.distance,999)
                + COALESCE(ahr_rl.distance,999),
            adj.pos
      LIMIT 1;

    IF FOUND THEN
        baseline_prox := aoupa.prox_adjustment;
    END IF;

    -- Now find any relative adjustments, and change the baseline prox based on them
    FOR aoupa IN
        SELECT  adj.*
          FROM  actor.org_unit_proximity_adjustment adj
                LEFT JOIN actor.org_unit_ancestors_distance(vacp_cl) acp_cl ON (acp_cl.id = adj.item_circ_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(vacn_ol) acn_ol ON (acn_ol.id = adj.item_owning_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(vacl_ol) acl_ol ON (acn_ol.id = adj.copy_location)
                LEFT JOIN actor.org_unit_ancestors_distance(pickup) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(request) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
          WHERE (adj.circ_mod IS NULL OR adj.circ_mod = vacp_cm) AND
                (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
                (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
                (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
                (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
                (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
                NOT absolute_adjustment AND
                COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity(
    ahr_id INT,
    acp_id BIGINT,
    copy_context_ou INT DEFAULT NULL
    -- TODO maybe? hold_context_ou INT DEFAULT NULL.  This would optionally
    -- support an "ahprox" measurement: adjust prox between copy circ lib and
    -- hold request lib, but I'm unsure whether to use this theoretical
    -- argument only in the baseline calculation or later in the other
    -- queries in this function.
) RETURNS NUMERIC AS $f$
DECLARE
    ahr  action.hold_request%ROWTYPE;
    acp  asset.copy%ROWTYPE;
    acn  asset.call_number%ROWTYPE;
    acl  asset.copy_location%ROWTYPE;

    prox NUMERIC;
BEGIN

    SELECT * INTO ahr FROM action.hold_request WHERE id = ahr_id;
    SELECT * INTO acp FROM asset.copy WHERE id = acp_id;
    SELECT * INTO acn FROM asset.call_number WHERE id = acp.call_number;
    SELECT * INTO acl FROM asset.copy_location WHERE id = acp.location;

    IF copy_context_ou IS NULL THEN
        copy_context_ou := acp.circ_lib;
    END IF;

    SELECT action.copy_calculated_proximity(
        ahr.pickup_lib,
        ahr.request_lib,
        copy_context_ou,
        acp.circ_modifier,
        acn.owning_lib,
        acl.owning_lib
    ) INTO prox;

    RETURN prox;
END;
$f$ LANGUAGE PLPGSQL;

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
    item_status_object  config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    calc_age_prox        actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    prox_ou           INT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
    hold_count        INT;
    hold_transit_prox    NUMERIC;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
    hold_penalty TEXT;
    v_pickup_ou ALIAS FOR pickup_ou;
    v_request_ou ALIAS FOR request_ou;
    item_prox INT;
    pickup_prox INT;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( v_pickup_ou );

    result.success := TRUE;

    -- The HOLD penalty block only applies to new holds.
    -- The CAPTURE penalty block applies to existing holds.
    hold_penalty := 'HOLD';
    IF retargetting THEN
        hold_penalty := 'CAPTURE';
    END IF;

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

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(v_pickup_ou, v_request_ou, match_item, match_user, match_requestor);
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

    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO item_status_object * FROM config.copy_status WHERE id = item_object.status;
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;

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

    IF item_object.holdable IS FALSE THEN
        result.fail_part := 'item.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_status_object.holdable IS FALSE THEN
        result.fail_part := 'status.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_location_object.holdable IS FALSE THEN
        result.fail_part := 'location.holdable';
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

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = v_pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Proximity of user's home_ou to the pickup_lib to see if penalty should be ignored.
    SELECT INTO pickup_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = v_pickup_ou;
    -- Proximity of user's home_ou to the items' lib to see if penalty should be ignored.
    IF hold_test.distance_is_from_owner THEN
        SELECT INTO item_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = item_cn_object.owning_lib;
    ELSE
        SELECT INTO item_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = item_object.circ_lib;
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND (csp.ignore_proximity IS NULL OR csp.ignore_proximity < item_prox
                     OR csp.ignore_proximity < pickup_prox)
                AND csp.block_list LIKE '%' || hold_penalty || '%' LOOP

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
                    AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
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
            SELECT INTO calc_age_prox * FROM actor.org_unit_setting WHERE name = 'circ.holds.calculated_age_proximity' AND org_unit = item_object.circ_lib;
            IF hold_test.distance_is_from_owner THEN
                prox_ou := item_cn_object.owning_lib;
            ELSE
                prox_ou := item_object.circ_lib;
            END IF;
            IF calc_age_prox.id IS NOT NULL AND calc_age_prox.value = 'true' THEN
                SELECT INTO hold_transit_prox action.copy_calculated_proximity(
                    v_pickup_ou,
                    v_request_ou,
                    prox_ou,
                    item_object.circ_modifier,
                    item_cn_object.owning_lib,
                    item_location_object.owning_lib
                );
            ELSE
                SELECT INTO hold_transit_prox prox::NUMERIC FROM actor.org_unit_proximity WHERE from_org = prox_ou AND to_org = v_pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox::NUMERIC THEN
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

COMMIT;


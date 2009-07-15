/*

-- If, for some reason, you need to reload this chunk of the schema
-- just use the following two statements to remove the tables before
-- running the rest of the file.  See 950.data.seed-values.sql for
-- the one default entry to add back to config.hold_matrix_matchpoint.

DROP TABLE config.hold_matrix_matchpoint CASCADE;
DROP TABLE config.hold_matrix_test CASCADE;

*/

BEGIN;


--
--                 ****** Which ruleset and tests to use *******
--
-- * Most specific range for org_unit and grp wins.
--
-- * circ_modifier match takes precidence over marc_type match, if circ_modifier is set here
--
-- * marc_type is first checked against the circ_as_type from the copy, then the item type from the marc record
--
-- * If neither circ_modifier nor marc_type is set (both are NULLABLE) then the entry defines the default
--   ruleset and tests for the OU + group (like BOOK in PINES)
--



CREATE TABLE config.hold_matrix_matchpoint (
    id                      SERIAL    PRIMARY KEY,
    active                  BOOL    NOT NULL DEFAULT TRUE,
    user_home_ou            INT        REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
    request_ou              INT        REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
    pickup_ou               INT        REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
    item_owning_ou          INT        REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
    item_circ_ou            INT        REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
    usr_grp                 INT        REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top applicable group from the group tree; will need descendents and prox functions for filtering
    requestor_grp           INT        NOT NULL REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top applicable group from the group tree; will need descendents and prox functions for filtering
    circ_modifier           TEXT    REFERENCES config.circ_modifier (code) DEFERRABLE INITIALLY DEFERRED,
    marc_type               TEXT    REFERENCES config.item_type_map (code) DEFERRABLE INITIALLY DEFERRED,
    marc_form               TEXT    REFERENCES config.item_form_map (code) DEFERRABLE INITIALLY DEFERRED,
    marc_vr_format          TEXT    REFERENCES config.videorecording_format_map (code) DEFERRABLE INITIALLY DEFERRED,
    juvenile_flag           BOOL,
    ref_flag                BOOL,
    holdable                BOOL    NOT NULL DEFAULT TRUE,                -- Hard "can't hold" flag requiring an override
    distance_is_from_owner  BOOL    NOT NULL DEFAULT FALSE,                -- How to calculate transit_range.  True means owning lib, false means copy circ lib
    transit_range           INT        REFERENCES actor.org_unit_type (id) DEFERRABLE INITIALLY DEFERRED,        -- Can circ inside range of cn.owner/cp.circ_lib at depth of the org_unit_type specified here
    max_holds               INT,                            -- Total hold requests must be less than this, NULL means skip (always pass)
    include_frozen_holds    BOOL    NOT NULL DEFAULT TRUE,                -- Include frozen hold requests in the count for max_holds test
    stop_blocked_user       BOOL    NOT NULL DEFAULT FALSE,                -- Stop users who cannot check out items from placing holds
    age_hold_protect_rule   INT        REFERENCES config.rule_age_hold_protect (id) DEFERRABLE INITIALLY DEFERRED,    -- still not sure we want to move this off the copy
    CONSTRAINT hous_once_per_grp_loc_mod_marc UNIQUE (user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, requestor_grp, usr_grp, circ_modifier, marc_type, marc_form, marc_vr_format, ref_flag, juvenile_flag)
);

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
                CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier OR item_object.circ_modifier IS NULL;
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

COMMIT;


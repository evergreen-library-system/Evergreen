BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0427'); -- gmc

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS INT AS $func$
DECLARE
    current_requestor_group    permission.grp_tree%ROWTYPE;
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
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO requestor_object * FROM actor.usr WHERE id = match_requestor;
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r WHERE r.record = item_cn_object.record;

    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.usr_not_requestor' AND enabled;

    IF NOT FOUND THEN
        SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = requestor_object.profile;
    ELSE
        SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = user_object.profile;
    END IF;

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
            IF current_mp.item_owning_ou IS NOT NULL THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_owning_ou, item_cn_object.owning_lib)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.item_circ_ou IS NOT NULL THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_circ_ou, item_object.circ_lib)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.pickup_ou IS NOT NULL THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.pickup_ou, pickup_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.request_ou IS NOT NULL THEN
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.request_ou, request_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.user_home_ou IS NOT NULL THEN
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

COMMIT;

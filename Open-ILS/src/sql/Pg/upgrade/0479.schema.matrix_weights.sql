BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0479');

CREATE OR REPLACE FUNCTION permission.grp_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE grp_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT pgt.parent, gad.distance+1
            FROM permission.grp_tree pgt JOIN grp_ancestors_distance gad ON pgt.id = gad.id
            WHERE pgt.parent IS NOT NULL
    )
    SELECT * FROM grp_ancestors_distance;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION permission.grp_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE grp_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT pgt.id, gdd.distance+1
            FROM permission.grp_tree pgt JOIN grp_descendants_distance gdd ON pgt.parent = gdd.id
    )
    SELECT * FROM grp_descendants_distance;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON ou.id = ouad.id
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT * FROM org_unit_ancestors_distance;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.id, oudd.distance+1
            FROM actor.org_unit ou JOIN org_unit_descendants_distance oudd ON ou.parent_ou = oudd.id
    )
    SELECT * FROM org_unit_descendants_distance;
$$ LANGUAGE SQL STABLE;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN user_home_ou         INT     REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE config.circ_matrix_weights (
    id                      SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    org_unit                NUMERIC(6,2)   NOT NULL,
    grp                     NUMERIC(6,2)   NOT NULL,
    circ_modifier           NUMERIC(6,2)   NOT NULL,
    marc_type               NUMERIC(6,2)   NOT NULL,
    marc_form               NUMERIC(6,2)   NOT NULL,
    marc_vr_format          NUMERIC(6,2)   NOT NULL,
    copy_circ_lib           NUMERIC(6,2)   NOT NULL,
    copy_owning_lib         NUMERIC(6,2)   NOT NULL,
    user_home_ou            NUMERIC(6,2)   NOT NULL,
    ref_flag                NUMERIC(6,2)   NOT NULL,
    juvenile_flag           NUMERIC(6,2)   NOT NULL,
    is_renewal              NUMERIC(6,2)   NOT NULL,
    usr_age_lower_bound     NUMERIC(6,2)   NOT NULL,
    usr_age_upper_bound     NUMERIC(6,2)   NOT NULL
);

CREATE TABLE config.hold_matrix_weights (
    id                      SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    user_home_ou            NUMERIC(6,2)   NOT NULL,
    request_ou              NUMERIC(6,2)   NOT NULL,
    pickup_ou               NUMERIC(6,2)   NOT NULL,
    item_owning_ou          NUMERIC(6,2)   NOT NULL,
    item_circ_ou            NUMERIC(6,2)   NOT NULL,
    usr_grp                 NUMERIC(6,2)   NOT NULL,
    requestor_grp           NUMERIC(6,2)   NOT NULL,
    circ_modifier           NUMERIC(6,2)   NOT NULL,
    marc_type               NUMERIC(6,2)   NOT NULL,
    marc_form               NUMERIC(6,2)   NOT NULL,
    marc_vr_format          NUMERIC(6,2)   NOT NULL,
    juvenile_flag           NUMERIC(6,2)   NOT NULL,
    ref_flag                NUMERIC(6,2)   NOT NULL
);

CREATE TABLE config.weight_assoc (
    id                      SERIAL  PRIMARY KEY,
    active                  BOOL    NOT NULL,
    org_unit                INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    circ_weights            INT     REFERENCES config.circ_matrix_weights (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    hold_weights            INT     REFERENCES config.hold_matrix_weights (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX cwa_one_active_per_ou ON config.weight_assoc (org_unit) WHERE active;

CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS config.circ_matrix_matchpoint AS $func$
DECLARE
    user_object     actor.usr%ROWTYPE;
    item_object     asset.copy%ROWTYPE;
    cn_object       asset.call_number%ROWTYPE;
    rec_descriptor  metabib.rec_descriptor%ROWTYPE;
    matchpoint      config.circ_matrix_matchpoint%ROWTYPE;
    weights         config.circ_matrix_weights%ROWTYPE;
    user_age        INTERVAL;
    denominator     INT;
BEGIN
    SELECT INTO user_object     * FROM actor.usr                WHERE id = match_user;
    SELECT INTO item_object     * FROM asset.copy               WHERE id = match_item;
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
        weights.grp                 := 11;
        weights.org_unit            := 10;
        weights.circ_modifier       := 5;
        weights.marc_type           := 4;
        weights.marc_form           := 3;
        weights.marc_vr_format      := 2;
        weights.copy_circ_lib       := 8;
        weights.copy_owning_lib     := 8;
        weights.user_home_ou        := 8;
        weights.ref_flag            := 1;
        weights.juvenile_flag       := 6;
        weights.is_renewal          := 7;
        weights.usr_age_lower_bound := 0;
        weights.usr_age_upper_bound := 0;
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

    -- Select the winning matchpoint into the matchpoint variable for returning
    SELECT INTO matchpoint m.*
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
            CASE WHEN upgad.distance        IS NOT NULL THEN 2^(2*weights.grp - (upgad.distance/denominator)) ELSE 0 END +
            -- Org Units
            CASE WHEN ctoua.distance        IS NOT NULL THEN 2^(2*weights.org_unit - (ctoua.distance/denominator)) ELSE 0 END +
            CASE WHEN cnoua.distance        IS NOT NULL THEN 2^(2*weights.copy_owning_lib - (cnoua.distance/denominator)) ELSE 0 END +
            CASE WHEN iooua.distance        IS NOT NULL THEN 2^(2*weights.copy_circ_lib - (iooua.distance/denominator)) ELSE 0 END +
            CASE WHEN uhoua.distance        IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0 END +
            -- Circ Type                    -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.is_renewal          IS NOT NULL THEN 4^weights.is_renewal ELSE 0 END +
            -- Static User Checks
            CASE WHEN m.juvenile_flag       IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0 END +
            CASE WHEN m.usr_age_lower_bound IS NOT NULL THEN 4^weights.usr_age_lower_bound ELSE 0 END +
            CASE WHEN m.usr_age_upper_bound IS NOT NULL THEN 4^weights.usr_age_upper_bound ELSE 0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier       IS NOT NULL THEN 4^weights.circ_modifier ELSE 0 END +
            CASE WHEN m.marc_type           IS NOT NULL THEN 4^weights.marc_type ELSE 0 END +
            CASE WHEN m.marc_form           IS NOT NULL THEN 4^weights.marc_form ELSE 0 END +
            CASE WHEN m.marc_vr_format      IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0 END +
            CASE WHEN m.ref_flag            IS NOT NULL THEN 4^weights.ref_flag ELSE 0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return the entire matchpoint
    RETURN matchpoint;
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
    rec_descriptor      metabib.rec_descriptor%ROWTYPE;
    matchpoint          config.hold_matrix_matchpoint%ROWTYPE;
    weights             config.hold_matrix_weights%ROWTYPE;
    denominator         INT;
BEGIN
    SELECT INTO user_object         * FROM actor.usr                WHERE id = match_user;
    SELECT INTO requestor_object    * FROM actor.usr                WHERE id = match_requestor;
    SELECT INTO item_object         * FROM asset.copy               WHERE id = match_item;
    SELECT INTO item_cn_object      * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor      * FROM metabib.rec_descriptor   WHERE record = item_cn_object.record;

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
               JOIN actor.org_unit_ancestors_distance( cn_object.owning_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    END IF;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.user_home_ou    := 5;
        weights.request_ou      := 5;
        weights.pickup_ou       := 5;
        weights.item_owning_ou  := 5;
        weights.item_circ_ou    := 5;
        weights.usr_grp         := 7;
        weights.requestor_grp   := 8;
        weights.circ_modifier   := 4;
        weights.marc_type       := 3;
        weights.marc_form       := 2;
        weights.marc_vr_format  := 1;
        weights.juvenile_flag   := 4;
        weights.ref_flag        := 0;
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
            AND (m.marc_vr_format       IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
            AND (m.ref_flag             IS NULL OR m.ref_flag = item_object.ref)
      ORDER BY
            -- Permission Groups
            CASE WHEN rpgad.distance    IS NOT NULL THEN 2^(2*weights.requestor_grp - (rpgad.distance/denominator)) ELSE 0 END +
            CASE WHEN upgad.distance    IS NOT NULL THEN 2^(2*weights.usr_grp - (upgad.distance/denominator)) ELSE 0 END +
            -- Org Units
            CASE WHEN puoua.distance    IS NOT NULL THEN 2^(2*weights.pickup_ou - (puoua.distance/denominator)) ELSE 0 END +
            CASE WHEN rqoua.distance    IS NOT NULL THEN 2^(2*weights.request_ou - (rqoua.distance/denominator)) ELSE 0 END +
            CASE WHEN cnoua.distance    IS NOT NULL THEN 2^(2*weights.item_owning_ou - (cnoua.distance/denominator)) ELSE 0 END +
            CASE WHEN iooua.distance    IS NOT NULL THEN 2^(2*weights.item_circ_ou - (iooua.distance/denominator)) ELSE 0 END +
            CASE WHEN uhoua.distance    IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0 END +
            -- Static User Checks       -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.juvenile_flag   IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier   IS NOT NULL THEN 4^weights.circ_modifier ELSE 0 END +
            CASE WHEN m.marc_type       IS NOT NULL THEN 4^weights.marc_type ELSE 0 END +
            CASE WHEN m.marc_form       IS NOT NULL THEN 4^weights.marc_form ELSE 0 END +
            CASE WHEN m.marc_vr_format  IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0 END +
            CASE WHEN m.ref_flag        IS NOT NULL THEN 4^weights.ref_flag ELSE 0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return just the ID for now
    RETURN matchpoint.id;
END;
$func$ LANGUAGE 'plpgsql';

INSERT INTO config.circ_matrix_weights(name, org_unit, grp, circ_modifier, marc_type, marc_form, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_upper_bound, usr_age_lower_bound) VALUES 
    ('Default', 10.0, 11.0, 5.0, 4.0, 3.0, 2.0, 8.0, 8.0, 8.0, 1.0, 6.0, 7.0, 0.0, 0.0),
    ('Org_Unit_First', 11.0, 10.0, 5.0, 4.0, 3.0, 2.0, 8.0, 8.0, 8.0, 1.0, 6.0, 7.0, 0.0, 0.0),
    ('Item_Owner_First', 8.0, 8.0, 5.0, 4.0, 3.0, 2.0, 10.0, 11.0, 8.0, 1.0, 6.0, 7.0, 0.0, 0.0),
    ('All_Equal', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

INSERT INTO config.hold_matrix_weights(name, user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_vr_format, juvenile_flag, ref_flag) VALUES
    ('Default', 5.0, 5.0, 5.0, 5.0, 5.0, 7.0, 8.0, 4.0, 3.0, 2.0, 1.0, 4.0, 0.0),
    ('Item_Owner_First', 5.0, 5.0, 5.0, 8.0, 7.0, 5.0, 5.0, 4.0, 3.0, 2.0, 1.0, 4.0, 0.0),
    ('User_Before_Requestor', 5.0, 5.0, 5.0, 5.0, 5.0, 8.0, 7.0, 4.0, 3.0, 2.0, 1.0, 4.0, 0.0),
    ('All_Equal', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

INSERT INTO config.weight_assoc(active, org_unit, circ_weights, hold_weights) VALUES
    (true, 1, 1, 1);

COMMIT;

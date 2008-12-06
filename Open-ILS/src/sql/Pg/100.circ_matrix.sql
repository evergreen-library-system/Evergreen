
BEGIN;

CREATE OR REPLACE FUNCTION explode_array(anyarray) RETURNS SETOF anyelement AS $BODY$
    SELECT ($1)[s] FROM generate_series(1, array_upper($1, 1)) AS s;
$BODY$
LANGUAGE 'sql' IMMUTABLE;

-- NOTE: current config.item_type should get sip2_media_type and magnetic_media columns

-- New table needed to handle circ modifiers inside the DB.  Will still require
-- central admin.  The circ_modifier column on asset.copy will become an fkey to this table.
CREATE TABLE config.circ_modifier (
    code            TEXT    PRIMARY KEY,
    name            TEXT    UNIQUE NOT NULL,
    description        TEXT    NOT NULL,
    sip2_media_type    TEXT    NOT NULL,
    magnetic_media    BOOL    NOT NULL DEFAULT TRUE
);

/*
-- for instance ...
INSERT INTO config.circ_modifier VALUES ( 'DVD', 'DVD', 'um ... DVDs', '001', FALSE );
INSERT INTO config.circ_modifier VALUES ( 'VIDEO', 'VIDEO', 'Tapes', '001', TRUE );
INSERT INTO config.circ_modifier VALUES ( 'BOOK', 'BOOK', 'Dead tree', '001', FALSE );
INSERT INTO config.circ_modifier VALUES ( 'CRAZY_ARL-ATH_SETTING', 'R2R_TAPE', 'reel2reel tape', '007', TRUE );
*/

-- But, just to get us started, use this
/*

UPDATE asset.copy SET circ_modifier = UPPER(circ_modifier) WHERE circ_modifier IS NOT NULL AND circ_modifier <> '';
UPDATE asset.copy SET circ_modifier = NULL WHERE circ_modifier = '';

INSERT INTO config.circ_modifier (code, name, description, sip2_media_type )
    SELECT DISTINCT
            UPPER(circ_modifier),
            UPPER(circ_modifier),
            LOWER(circ_modifier),
            '001'
      FROM  asset.copy
      WHERE circ_modifier IS NOT NULL;

*/

-- add an fkey pointing to the new circ mod table
ALTER TABLE asset.copy ADD CONSTRAINT circ_mod_fkey FOREIGN KEY (circ_modifier) REFERENCES config.circ_modifier (code) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- config table to hold the vr_format names
CREATE TABLE config.videorecording_format_map (
    code    TEXT    PRIMARY KEY,
    value    TEXT    NOT NULL
);

INSERT INTO config.videorecording_format_map VALUES ('a','Beta');
INSERT INTO config.videorecording_format_map VALUES ('b','VHS');
INSERT INTO config.videorecording_format_map VALUES ('c','U-matic');
INSERT INTO config.videorecording_format_map VALUES ('d','EIAJ');
INSERT INTO config.videorecording_format_map VALUES ('e','Type C');
INSERT INTO config.videorecording_format_map VALUES ('f','Quadruplex');
INSERT INTO config.videorecording_format_map VALUES ('g','Laserdisc');
INSERT INTO config.videorecording_format_map VALUES ('h','CED');
INSERT INTO config.videorecording_format_map VALUES ('i','Betacam');
INSERT INTO config.videorecording_format_map VALUES ('j','Betacam SP');
INSERT INTO config.videorecording_format_map VALUES ('k','Super-VHS');
INSERT INTO config.videorecording_format_map VALUES ('m','M-II');
INSERT INTO config.videorecording_format_map VALUES ('o','D-2');
INSERT INTO config.videorecording_format_map VALUES ('p','8 mm.');
INSERT INTO config.videorecording_format_map VALUES ('q','Hi-8 mm.');
INSERT INTO config.videorecording_format_map VALUES ('u','Unknown');
INSERT INTO config.videorecording_format_map VALUES ('v','DVD');
INSERT INTO config.videorecording_format_map VALUES ('z','Other');



/**
 **  Here we define the tables that make up the circ matrix.  Conceptually, this implements
 **  the "sparse matrix" that everyone talks about, instead of using traditional rules logic.
 **  Physically, we cut the matrix up into separate tables (almost 3rd normal form!) that handle
 **  different portions of the matrix.  This wil simplify creation of the UI (I hope), and help the
 **  developers focus on specific parts of the matrix.
 **/


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

CREATE TABLE config.circ_matrix_matchpoint (
    id                   SERIAL    PRIMARY KEY,
    active               BOOL    NOT NULL DEFAULT TRUE,
    org_unit             INT        NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
    grp                  INT     NOT NULL REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED,    -- Set to the top applicable group from the group tree; will need descendents and prox functions for filtering
    circ_modifier        TEXT    REFERENCES config.circ_modifier (code) DEFERRABLE INITIALLY DEFERRED,
    marc_type            TEXT    REFERENCES config.item_type_map (code) DEFERRABLE INITIALLY DEFERRED,
    marc_form            TEXT    REFERENCES config.item_form_map (code) DEFERRABLE INITIALLY DEFERRED,
    marc_vr_format       TEXT    REFERENCES config.videorecording_format_map (code) DEFERRABLE INITIALLY DEFERRED,
    ref_flag             BOOL,
    juvenile_flag        BOOL,
    is_renewal           BOOL,
    usr_age_lower_bound  INTERVAL,
    usr_age_upper_bound  INTERVAL,
    circulate            BOOL    NOT NULL DEFAULT TRUE,    -- Hard "can't circ" flag requiring an override
    duration_rule        INT     NOT NULL REFERENCES config.rule_circ_duration (id) DEFERRABLE INITIALLY DEFERRED,
    recurring_fine_rule  INT     NOT NULL REFERENCES config.rule_recuring_fine (id) DEFERRABLE INITIALLY DEFERRED,
    max_fine_rule        INT     NOT NULL REFERENCES config.rule_max_fine (id) DEFERRABLE INITIALLY DEFERRED,
    script_test          TEXT,                           -- javascript source 
    CONSTRAINT ep_once_per_grp_loc_mod_marc UNIQUE (grp, org_unit, circ_modifier, marc_type, marc_form, marc_vr_format, ref_flag, juvenile_flag, usr_age_lower_bound, usr_age_upper_bound, is_renewal)
);


-- Tests for max items out by circ_modifier
CREATE TABLE config.circ_matrix_circ_mod_test (
    id          SERIAL     PRIMARY KEY,
    matchpoint  INT     NOT NULL REFERENCES config.circ_matrix_matchpoint (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    items_out   INT     NOT NULL,                            -- Total current active circulations must be less than this, NULL means skip (always pass)
    circ_mod    TEXT    NOT NULL REFERENCES config.circ_modifier (code) ON DELETE CASCADE ON UPDATE CASCADE  DEFERRABLE INITIALLY DEFERRED-- circ_modifier type that the max out applies to
);


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


CREATE TYPE action.matrix_test_result AS ( success BOOL, matchpoint INT, fail_part TEXT );
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
            AND (circ.stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE') OR circ.stop_fines IS NULL)
            AND cp.circ_modifier = out_by_circ_mod.circ_mod;
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

CREATE OR REPLACE FUNCTION action.item_user_circ_test( INT, BIGINT, INT ) RETURNS SETOF action.matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, FALSE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.item_user_renew_test( INT, BIGINT, INT ) RETURNS SETOF action.matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, TRUE );
$func$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION actor.calculate_system_penalties( match_user INT, context_org INT ) RETURNS SETOF actor.usr_standing_penalty AS $func$
DECLARE
    user_object         actor.usr%ROWTYPE;
    new_sp_row             actor.usr_standing_penalty%ROWTYPE;
    existing_sp_row        actor.usr_standing_penalty%ROWTYPE;
    max_fines           permission.grp_penalty_threshold%ROWTYPE;
    max_overdue         permission.grp_penalty_threshold%ROWTYPE;
    max_items_out       permission.grp_penalty_threshold%ROWTYPE;
    tmp_grp              INT;
    items_overdue        INT;
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
                        AND standing_penalty = 1
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        FOR tmp_groc IN
                SELECT  *
                  FROM  money.grocery g
                        JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                  WHERE usr = match_user
                        AND xact_finish IS NULL
                LOOP
            SELECT INTO tmp_fines SUM( amount ) FROM money.billing WHERE xact = tmp_groc.id AND NOT voided;
            current_fines = current_fines + COALESCE(tmp_fines, 0.0);
            SELECT INTO tmp_fines SUM( amount ) FROM money.payment WHERE xact = tmp_groc.id AND NOT voided;
            current_fines = current_fines - COALESCE(tmp_fines, 0.0);
        END LOOP;

        FOR tmp_circ IN
                SELECT  *
                  FROM  action.circulation circ
                        JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                  WHERE usr = match_user
                        AND xact_finish IS NULL
                LOOP
            SELECT INTO tmp_fines SUM( amount ) FROM money.billing WHERE xact = tmp_circ.id AND NOT voided;
            current_fines = current_fines + COALESCE(tmp_fines, 0.0);
            SELECT INTO tmp_fines SUM( amount ) FROM money.payment WHERE xact = tmp_circ.id AND NOT voided;
            current_fines = current_fines - COALESCE(tmp_fines, 0.0);
        END LOOP;

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
            AND (circ.stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE') OR circ.stop_fines IS NULL);

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
                        AND standing_penalty = 3
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_items_out.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
                AND circ.checkin_time IS NULL
                AND (circ.stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE') OR circ.stop_fines IS NULL);

           IF items_out >= max_items_out.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_items_out.org_unit;
            new_sp_row.standing_penalty := 3;
            RETURN NEXT new_sp_row;
           END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

COMMIT;


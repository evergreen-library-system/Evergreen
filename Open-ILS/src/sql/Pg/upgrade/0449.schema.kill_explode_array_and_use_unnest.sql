
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0449'); -- miker

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
    hold_ratio          action.hold_stats%ROWTYPE;
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
        result.fail_part := 'no_item';
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

    -- Fail if the total copy-hold ratio is too low
    IF circ_test.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_test.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_test.available_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_test.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
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
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
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
    tmp_penalty         config.standing_penalty%ROWTYPE;
    tmp_depth           INTEGER;
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

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 1;

        SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
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

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_overdue.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 2;

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

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_items_out.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 3;

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

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 4;

        SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 4;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for in collections
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Remove the in-collections penalty if the user has paid down enough
    -- This penalty is different, because this code is not responsible for creating 
    -- new in-collections penalties, only for removing them
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 30 AND org_unit = tmp_org.id;

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

        SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        -- first, see if the user had paid down to the threshold
        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines IS NULL OR current_fines <= max_fines.threshold THEN
            -- patron has paid down enough

            SELECT INTO tmp_penalty * FROM config.standing_penalty WHERE id = 30;

            IF tmp_penalty.org_depth IS NOT NULL THEN

                -- since this code is not responsible for applying the penalty, it can't 
                -- guarantee the current context org will match the org at which the penalty 
                --- was applied.  search up the org tree until we hit the configured penalty depth
                SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;
                SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;

                WHILE tmp_depth >= tmp_penalty.org_depth LOOP

                    RETURN QUERY
                        SELECT  *
                          FROM  actor.usr_standing_penalty
                          WHERE usr = match_user
                                AND org_unit = tmp_org.id
                                AND (stop_date IS NULL or stop_date > NOW())
                                AND standing_penalty = 30;

                    IF tmp_org.parent_ou IS NULL THEN
                        EXIT;
                    END IF;

                    SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;
                    SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;
                END LOOP;

            ELSE

                -- no penalty depth is defined, look for exact matches

                RETURN QUERY
                    SELECT  *
                      FROM  actor.usr_standing_penalty
                      WHERE usr = match_user
                            AND org_unit = max_fines.org_unit
                            AND (stop_date IS NULL or stop_date > NOW())
                            AND standing_penalty = 30;
            END IF;
    
        END IF;

    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

COMMIT;


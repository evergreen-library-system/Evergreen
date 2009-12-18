BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0118');

INSERT INTO config.standing_penalty (id,name,label) VALUES (30,'PATRON_IN_COLLECTIONS','Patron has been referred to a collections agency');

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

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_fines.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 1
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (r.pickup_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
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

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_overdue.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
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

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_items_out.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 3
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

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

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_fines.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 4
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (r.pickup_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL ) l USING (id);

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

        -- first, see if the user had paid down to the threshold
        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (r.pickup_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL ) l USING (id);

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

                    FOR existing_sp_row IN
                            SELECT  *
                            FROM  actor.usr_standing_penalty
                            WHERE usr = match_user
                                    AND org_unit = tmp_org.id
                                    AND (stop_date IS NULL or stop_date > NOW())
                                    AND standing_penalty = 30 
                            LOOP

                        -- Penalty exists, return it for removal
                        RETURN NEXT existing_sp_row;
                    END LOOP;

                    IF tmp_org.parent_ou IS NULL THEN
                        EXIT;
                    END IF;

                    SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;
                    SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;
                END LOOP;

            ELSE

                -- no penalty depth is defined, look for exact matches

                FOR existing_sp_row IN
                        SELECT  *
                        FROM  actor.usr_standing_penalty
                        WHERE usr = match_user
                                AND org_unit = max_fines.org_unit
                                AND (stop_date IS NULL or stop_date > NOW())
                                AND standing_penalty = 30 
                        LOOP
                    -- Penalty exists, return it for removal
                    RETURN NEXT existing_sp_row;
                END LOOP;
            END IF;
    
        END IF;

    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


COMMIT;

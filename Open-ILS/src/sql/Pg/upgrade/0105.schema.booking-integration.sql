BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0105'); -- miker

CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('reservation');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS
    SELECT  xact.id AS id,
        xact.usr AS usr,
        COALESCE(circ.circ_lib,groc.billing_location,res.pickup_lib) AS billing_location,
        xact.xact_start AS xact_start,
        xact.xact_finish AS xact_finish,
        SUM(credit.amount) AS total_paid,
        MAX(credit.payment_ts) AS last_payment_ts,
        LAST(credit.note) AS last_payment_note,
        LAST(credit.payment_type) AS last_payment_type,
        SUM(debit.amount) AS total_owed,
        MAX(debit.billing_ts) AS last_billing_ts,
        LAST(debit.note) AS last_billing_note,
        LAST(debit.billing_type) AS last_billing_type,
        COALESCE(SUM(debit.amount),0) - COALESCE(SUM(credit.amount),0) AS balance_owed,
        p.relname AS xact_type
      FROM  money.billable_xact xact
        JOIN pg_class p ON (xact.tableoid = p.oid)
        LEFT JOIN "action".circulation circ ON (circ.id = xact.id)
        LEFT JOIN money.grocery groc ON (groc.id = xact.id)
        LEFT JOIN booking.reservation res ON (groc.id = xact.id)
        LEFT JOIN (
            SELECT  billing.xact,
                billing.voided,
                sum(billing.amount) AS amount,
                max(billing.billing_ts) AS billing_ts,
                last(billing.note) AS note,
                last(billing.billing_type) AS billing_type
              FROM  money.billing
              WHERE billing.voided IS FALSE
              GROUP BY billing.xact, billing.voided
        ) debit ON (xact.id = debit.xact AND debit.voided IS FALSE)
        LEFT JOIN (
            SELECT  payment_view.xact,
                payment_view.voided,
                sum(payment_view.amount) AS amount,
                max(payment_view.payment_ts) AS payment_ts,
                last(payment_view.note) AS note,
                last(payment_view.payment_type) AS payment_type
              FROM  money.payment_view
              WHERE payment_view.voided IS FALSE
              GROUP BY payment_view.xact, payment_view.voided
        ) credit ON (xact.id = credit.xact AND credit.voided IS FALSE)
      WHERE xact.xact_finish IS NULL
      GROUP BY 1,2,3,4,5,15
      ORDER BY MAX(debit.billing_ts), MAX(credit.payment_ts);

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


    RETURN;
END;
$func$ LANGUAGE plpgsql;

COMMIT;


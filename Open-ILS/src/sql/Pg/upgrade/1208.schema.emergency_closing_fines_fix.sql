BEGIN;

SELECT evergreen.upgrade_deps_block_check('1208', :eg_version);

CREATE OR REPLACE FUNCTION action.emergency_closing_stage_2_circ ( circ_closing_entry INT )
    RETURNS BOOL AS $$
DECLARE
    circ            action.circulation%ROWTYPE;
    e_closing       action.emergency_closing%ROWTYPE;
    e_c_circ        action.emergency_closing_circulation%ROWTYPE;
    closing         actor.org_unit_closed%ROWTYPE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    bill            money.billing%ROWTYPE;
    last_bill       money.billing%ROWTYPE;
    day_number      INT;
    hoo_close       TIME WITHOUT TIME ZONE;
    plus_days       INT;
    avoid_negative  BOOL;
    extend_grace    BOOL;
    new_due_date    TEXT;
BEGIN
    -- Gather objects involved
    SELECT  * INTO e_c_circ
      FROM  action.emergency_closing_circulation
      WHERE id = circ_closing_entry;

    IF e_c_circ.process_time IS NOT NULL THEN
        -- Already processed ... moving on
        RETURN FALSE;
    END IF;

    SELECT  * INTO e_closing
      FROM  action.emergency_closing
      WHERE id = e_c_circ.emergency_closing;

    IF e_closing.process_start_time IS NULL THEN
        -- Huh... that's odd. And wrong.
        RETURN FALSE;
    END IF;

    SELECT  * INTO closing
      FROM  actor.org_unit_closed
      WHERE emergency_closing = e_closing.id;

    SELECT  * INTO circ
      FROM  action.circulation
      WHERE id = e_c_circ.circulation;

    -- Record the processing
    UPDATE  action.emergency_closing_circulation
      SET   original_due_date = circ.due_date,
            process_time = NOW()
      WHERE id = circ_closing_entry;

    UPDATE  action.emergency_closing
      SET   last_update_time = NOW()
      WHERE id = e_closing.id;

    SELECT value::BOOL INTO avoid_negative FROM actor.org_unit_ancestor_setting('bill.prohibit_negative_balance_on_overdues', circ.circ_lib);
    SELECT value::BOOL INTO extend_grace FROM actor.org_unit_ancestor_setting('circ.grace.extend', circ.circ_lib);

    new_due_date := evergreen.find_next_open_time( closing.org_unit, circ.due_date, EXTRACT(EPOCH FROM circ.duration)::INT % 86400 > 0 )::TEXT;
    UPDATE action.circulation SET due_date = new_due_date::TIMESTAMPTZ WHERE id = circ.id;

    -- Now, see if we need to get rid of some fines
    SELECT  * INTO last_bill
      FROM  money.billing b
      WHERE b.xact = circ.id
            AND NOT b.voided
            AND b.btype = 1
      ORDER BY billing_ts DESC
      LIMIT 1;

    FOR bill IN
        SELECT  *
          FROM  money.billing b
          WHERE b.xact = circ.id
                AND b.btype = 1
                AND NOT b.voided
                AND (
                    b.billing_ts BETWEEN closing.close_start AND new_due_date::TIMESTAMPTZ
                    OR (extend_grace AND last_bill.billing_ts <= new_due_date::TIMESTAMPTZ + circ.grace_period)
                )
                AND NOT EXISTS (SELECT 1 FROM money.account_adjustment a WHERE a.billing = b.id)
          ORDER BY billing_ts
    LOOP
        IF avoid_negative THEN
            PERFORM FROM money.materialized_billable_xact_summary WHERE id = circ.id AND balance_owed < bill.amount;
            EXIT WHEN FOUND; -- We can't go negative, and voiding this bill would do that...
        END IF;

        UPDATE  money.billing
          SET   voided = TRUE,
                void_time = NOW(),
                note = COALESCE(note,'') || ' :: Voided by emergency closing handler'
          WHERE id = bill.id;
    END LOOP;
    
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.emergency_closing_stage_2_reservation ( res_closing_entry INT )
    RETURNS BOOL AS $$
DECLARE
    res             booking.reservation%ROWTYPE;
    e_closing       action.emergency_closing%ROWTYPE;
    e_c_res         action.emergency_closing_reservation%ROWTYPE;
    closing         actor.org_unit_closed%ROWTYPE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    bill            money.billing%ROWTYPE;
    day_number      INT;
    hoo_close       TIME WITHOUT TIME ZONE;
    plus_days       INT;
    avoid_negative  BOOL;
    new_due_date    TEXT;
BEGIN
    -- Gather objects involved
    SELECT  * INTO e_c_res
      FROM  action.emergency_closing_reservation
      WHERE id = res_closing_entry;

    IF e_c_res.process_time IS NOT NULL THEN
        -- Already processed ... moving on
        RETURN FALSE;
    END IF;

    SELECT  * INTO e_closing
      FROM  action.emergency_closing
      WHERE id = e_c_res.emergency_closing;

    IF e_closing.process_start_time IS NULL THEN
        -- Huh... that's odd. And wrong.
        RETURN FALSE;
    END IF;

    SELECT  * INTO closing
      FROM  actor.org_unit_closed
      WHERE emergency_closing = e_closing.id;

    SELECT  * INTO res
      FROM  booking.reservation
      WHERE id = e_c_res.reservation;

    IF res.pickup_lib IS NULL THEN -- Need to be far enough along to have a pickup lib
        RETURN FALSE;
    END IF;

    -- Record the processing
    UPDATE  action.emergency_closing_reservation
      SET   original_end_time = res.end_time,
            process_time = NOW()
      WHERE id = res_closing_entry;

    UPDATE  action.emergency_closing
      SET   last_update_time = NOW()
      WHERE id = e_closing.id;

    SELECT value::BOOL INTO avoid_negative FROM actor.org_unit_ancestor_setting('bill.prohibit_negative_balance_on_overdues', res.pickup_lib);

    new_due_date := evergreen.find_next_open_time( closing.org_unit, res.end_time, EXTRACT(EPOCH FROM res.booking_interval)::INT % 86400 > 0 )::TEXT;
    UPDATE booking.reservation SET end_time = new_due_date::TIMESTAMPTZ WHERE id = res.id;

    -- Now, see if we need to get rid of some fines
    FOR bill IN
        SELECT  *
          FROM  money.billing b
          WHERE b.xact = res.id
                AND b.btype = 1
                AND NOT b.voided
                AND b.billing_ts BETWEEN closing.close_start AND new_due_date::TIMESTAMPTZ
                AND NOT EXISTS (SELECT 1 FROM money.account_adjustment a WHERE a.billing = b.id)
    LOOP
        IF avoid_negative THEN
            PERFORM FROM money.materialized_billable_xact_summary WHERE id = res.id AND balance_owed < bill.amount;
            EXIT WHEN FOUND; -- We can't go negative, and voiding this bill would do that...
        END IF;

        UPDATE  money.billing
          SET   voided = TRUE,
                void_time = NOW(),
                note = COALESCE(note,'') || ' :: Voided by emergency closing handler'
          WHERE id = bill.id;
    END LOOP;
    
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;


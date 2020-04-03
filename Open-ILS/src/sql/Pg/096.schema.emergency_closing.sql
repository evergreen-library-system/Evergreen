/*
 * Copyright (C) 2018  Equinox Open Library Initiative Inc.
 * Mike Rylander <mrylander@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

BEGIN;

CREATE TABLE action.emergency_closing (
    id                  SERIAL      PRIMARY KEY,
    creator             INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    process_start_time  TIMESTAMPTZ,
    process_end_time    TIMESTAMPTZ,
    last_update_time    TIMESTAMPTZ
);

ALTER TABLE actor.org_unit_closed
    ADD COLUMN emergency_closing INT
        REFERENCES action.emergency_closing (id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE action.emergency_closing_circulation (
    id                  BIGSERIAL   PRIMARY KEY,
    emergency_closing   INT         NOT NULL REFERENCES action.emergency_closing (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    circulation         INT         NOT NULL REFERENCES action.circulation (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    original_due_date   TIMESTAMPTZ,
    process_time        TIMESTAMPTZ
);
CREATE INDEX emergency_closing_circulation_emergency_closing_idx ON action.emergency_closing_circulation (emergency_closing);
CREATE INDEX emergency_closing_circulation_circulation_idx ON action.emergency_closing_circulation (circulation);

CREATE TABLE action.emergency_closing_reservation (
    id                  BIGSERIAL   PRIMARY KEY,
    emergency_closing   INT         NOT NULL REFERENCES action.emergency_closing (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    reservation         INT         NOT NULL REFERENCES booking.reservation (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    original_end_time   TIMESTAMPTZ,
    process_time        TIMESTAMPTZ
);
CREATE INDEX emergency_closing_reservation_emergency_closing_idx ON action.emergency_closing_reservation (emergency_closing);
CREATE INDEX emergency_closing_reservation_reservation_idx ON action.emergency_closing_reservation (reservation);

CREATE TABLE action.emergency_closing_hold (
    id                  BIGSERIAL   PRIMARY KEY,
    emergency_closing   INT         NOT NULL REFERENCES action.emergency_closing (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    hold                INT         NOT NULL REFERENCES action.hold_request (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    original_shelf_expire_time   TIMESTAMPTZ,
    process_time        TIMESTAMPTZ
);
CREATE INDEX emergency_closing_hold_emergency_closing_idx ON action.emergency_closing_hold (emergency_closing);
CREATE INDEX emergency_closing_hold_hold_idx ON action.emergency_closing_hold (hold);

CREATE OR REPLACE VIEW action.emergency_closing_status AS
    SELECT  e.*,
            COALESCE(c.count, 0) AS circulations,
            COALESCE(c.completed, 0) AS circulations_complete,
            COALESCE(b.count, 0) AS reservations,
            COALESCE(b.completed, 0) AS reservations_complete,
            COALESCE(h.count, 0) AS holds,
            COALESCE(h.completed, 0) AS holds_complete
      FROM  action.emergency_closing e
            LEFT JOIN (SELECT emergency_closing, count(*) count, SUM((process_time IS NOT NULL)::INT) completed FROM action.emergency_closing_circulation GROUP BY 1) c ON (c.emergency_closing = e.id)
            LEFT JOIN (SELECT emergency_closing, count(*) count, SUM((process_time IS NOT NULL)::INT) completed FROM action.emergency_closing_reservation GROUP BY 1) b ON (b.emergency_closing = e.id)
            LEFT JOIN (SELECT emergency_closing, count(*) count, SUM((process_time IS NOT NULL)::INT) completed FROM action.emergency_closing_hold GROUP BY 1) h ON (h.emergency_closing = e.id)
;

CREATE OR REPLACE FUNCTION evergreen.find_next_open_time ( circ_lib INT, initial TIMESTAMPTZ, hourly BOOL DEFAULT FALSE, initial_time TIME DEFAULT NULL, dow_count INT DEFAULT 0 )
    RETURNS TIMESTAMPTZ AS $$
DECLARE
    day_number      INT;
    plus_days       INT;
    final_time      TEXT;
    time_adjusted   BOOL;
    hoo_open        TIME WITHOUT TIME ZONE;
    hoo_close       TIME WITHOUT TIME ZONE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    breakout        INT := 0;
BEGIN

    IF dow_count > 6 THEN
        RETURN initial;
    END IF;

    IF initial_time IS NULL THEN
        initial_time := initial::TIME;
    END IF;

    final_time := (initial + '1 second'::INTERVAL)::TEXT;
    LOOP
        breakout := breakout + 1;

        time_adjusted := FALSE;

        IF dow_count > 0 THEN -- we're recursing, so check for HOO closing
            day_number := EXTRACT(ISODOW FROM final_time::TIMESTAMPTZ) - 1;
            plus_days := 0;
            FOR i IN 1..7 LOOP
                EXECUTE 'SELECT dow_' || day_number || '_open, dow_' || day_number || '_close FROM actor.hours_of_operation WHERE id = $1'
                    INTO hoo_open, hoo_close
                    USING circ_lib;

                -- RAISE NOTICE 'initial time: %; dow: %; close: %',initial_time,day_number,hoo_close;

                IF hoo_close = '00:00:00' THEN -- bah ... I guess we'll check the next day
                    day_number := (day_number + 1) % 7;
                    plus_days := plus_days + 1;
                    time_adjusted := TRUE;
                    CONTINUE;
                END IF;

                IF hoo_close IS NULL THEN -- no hours of operation ... assume no closing?
                    hoo_close := '23:59:59';
                END IF;

                EXIT;
            END LOOP;

            final_time := DATE(final_time::TIMESTAMPTZ + (plus_days || ' days')::INTERVAL)::TEXT;
            IF hoo_close <> '00:00:00' AND hourly THEN -- Not a day-granular circ
                final_time := final_time||' '|| hoo_close;
            ELSE
                final_time := final_time||' 23:59:59';
            END IF;
        END IF;

        -- Loop through other closings
        LOOP
            SELECT * INTO adjacent FROM actor.org_unit_closed WHERE org_unit = circ_lib AND final_time::TIMESTAMPTZ between close_start AND close_end;
            EXIT WHEN adjacent.id IS NULL;
            time_adjusted := TRUE;
            -- RAISE NOTICE 'recursing for closings with final_time: %',final_time;
            final_time := evergreen.find_next_open_time(circ_lib, adjacent.close_end::TIMESTAMPTZ, hourly, initial_time, dow_count + 1)::TEXT;
        END LOOP;

        EXIT WHEN breakout > 100;
        EXIT WHEN NOT time_adjusted;

    END LOOP;

    RETURN final_time;
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE action.emergency_closing_stage_1_count AS (circulations INT, reservations INT, holds INT);
CREATE OR REPLACE FUNCTION action.emergency_closing_stage_1 ( e_closing INT )
    RETURNS SETOF action.emergency_closing_stage_1_count AS $$
DECLARE
    tmp     INT;
    touched action.emergency_closing_stage_1_count%ROWTYPE;
BEGIN
    -- First, gather circs
    INSERT INTO action.emergency_closing_circulation (emergency_closing, circulation)
        SELECT  e_closing,
                circ.id
          FROM  actor.org_unit_closed closing
                JOIN action.emergency_closing ec ON (closing.emergency_closing = ec.id AND ec.id = e_closing)
                JOIN action.circulation circ ON (
                    circ.circ_lib = closing.org_unit
                    AND circ.due_date BETWEEN closing.close_start AND (closing.close_end + '1s'::INTERVAL)
                    AND circ.xact_finish IS NULL
                )
          WHERE NOT EXISTS (SELECT 1 FROM action.emergency_closing_circulation t WHERE t.emergency_closing = e_closing AND t.circulation = circ.id);

    GET DIAGNOSTICS tmp = ROW_COUNT;
    touched.circulations := tmp;

    INSERT INTO action.emergency_closing_reservation (emergency_closing, reservation)
        SELECT  e_closing,
                res.id
          FROM  actor.org_unit_closed closing
                JOIN action.emergency_closing ec ON (closing.emergency_closing = ec.id AND ec.id = e_closing)
                JOIN booking.reservation res ON (
                    res.pickup_lib = closing.org_unit
                    AND res.end_time BETWEEN closing.close_start AND (closing.close_end + '1s'::INTERVAL)
                )
          WHERE NOT EXISTS (SELECT 1 FROM action.emergency_closing_reservation t WHERE t.emergency_closing = e_closing AND t.reservation = res.id);

    GET DIAGNOSTICS tmp = ROW_COUNT;
    touched.reservations := tmp;

    INSERT INTO action.emergency_closing_hold (emergency_closing, hold)
        SELECT  e_closing,
                hold.id
          FROM  actor.org_unit_closed closing
                JOIN action.emergency_closing ec ON (closing.emergency_closing = ec.id AND ec.id = e_closing)
                JOIN action.hold_request hold ON (
                    pickup_lib = closing.org_unit
                    AND hold.shelf_expire_time BETWEEN closing.close_start AND (closing.close_end + '1s'::INTERVAL)
                    AND hold.fulfillment_time IS NULL
                    AND hold.cancel_time IS NULL
                )
          WHERE NOT EXISTS (SELECT 1 FROM action.emergency_closing_hold t WHERE t.emergency_closing = e_closing AND t.hold = hold.id);

    GET DIAGNOSTICS tmp = ROW_COUNT;
    touched.holds := tmp;

    UPDATE  action.emergency_closing
      SET   process_start_time = NOW(),
            last_update_time = NOW()
      WHERE id = e_closing;

    RETURN NEXT touched;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.emergency_closing_stage_2_hold ( hold_closing_entry INT )
    RETURNS BOOL AS $$
DECLARE
    hold        action.hold_request%ROWTYPE;
    e_closing   action.emergency_closing%ROWTYPE;
    e_c_hold    action.emergency_closing_hold%ROWTYPE;
    closing     actor.org_unit_closed%ROWTYPE;
    day_number  INT;
    hoo_close   TIME WITHOUT TIME ZONE;
    plus_days   INT;
BEGIN
    -- Gather objects involved
    SELECT  * INTO e_c_hold
      FROM  action.emergency_closing_hold
      WHERE id = hold_closing_entry;

    IF e_c_hold.process_time IS NOT NULL THEN
        -- Already processed ... moving on
        RETURN FALSE;
    END IF;

    SELECT  * INTO e_closing
      FROM  action.emergency_closing
      WHERE id = e_c_hold.emergency_closing;

    IF e_closing.process_start_time IS NULL THEN
        -- Huh... that's odd. And wrong.
        RETURN FALSE;
    END IF;

    SELECT  * INTO closing
      FROM  actor.org_unit_closed
      WHERE emergency_closing = e_closing.id;

    SELECT  * INTO hold
      FROM  action.hold_request h
      WHERE id = e_c_hold.hold;

    -- Record the processing
    UPDATE  action.emergency_closing_hold
      SET   original_shelf_expire_time = hold.shelf_expire_time,
            process_time = NOW()
      WHERE id = hold_closing_entry;

    UPDATE  action.emergency_closing
      SET   last_update_time = NOW()
      WHERE id = e_closing.id;

    UPDATE  action.hold_request
      SET   shelf_expire_time = evergreen.find_next_open_time(closing.org_unit, hold.shelf_expire_time, TRUE)
      WHERE id = hold.id;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

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


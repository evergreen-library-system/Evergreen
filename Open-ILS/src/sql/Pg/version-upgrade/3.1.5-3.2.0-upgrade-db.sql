--Upgrade Script for 3.1.5 to 3.2.0
\set eg_version '''3.2.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.2.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1115', :eg_version);

INSERT INTO permission.perm_list (id,code,description) VALUES ( 607, 'EMERGENCY_CLOSING', 'Create and manage Emergency Closings');

INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkout.due.emergency_closing','aecc','Circulation due date was adjusted by the Emergency Closing handler');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.shelf_expire.emergency_closing','aech','Hold shelf expire time was adjusted by the Emergency Closing handler');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('booking.due.emergency_closing','aecr','Booking reservation return date was adjusted by the Emergency Closing handler');

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
            PERFORM FROM money.materialized_billable_xact_summary WHERE id = circ.id AND balanced_owd < bill.amount;
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
            PERFORM FROM money.materialized_billable_xact_summary WHERE id = res.id AND balanced_owd < bill.amount;
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



CREATE TYPE actor.cascade_setting_summary AS (
    name TEXT,
    value JSON,
    has_org_setting BOOLEAN,
    has_user_setting BOOLEAN,
    has_workstation_setting BOOLEAN
);

SELECT evergreen.upgrade_deps_block_check('1116', :eg_version);

CREATE TABLE config.workstation_setting_type (
    name            TEXT    PRIMARY KEY,
    label           TEXT    UNIQUE NOT NULL,
    grp             TEXT    REFERENCES config.settings_group (name),
    description     TEXT,
    datatype        TEXT    NOT NULL DEFAULT 'string',
    fm_class        TEXT,
    --
    -- define valid datatypes
    --
    CONSTRAINT cwst_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
      'date', 'string', 'object', 'array', 'link' ) ),
    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT cwst_no_empty_link CHECK
    ( ( datatype =  'link' AND fm_class IS NOT NULL ) OR
      ( datatype <> 'link' AND fm_class IS NULL ) )
);

CREATE TABLE actor.workstation_setting (
    id          SERIAL PRIMARY KEY,
    workstation INT    NOT NULL REFERENCES actor.workstation (id) 
                       ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT   NOT NULL REFERENCES config.workstation_setting_type (name) 
                       ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    value       JSON   NOT NULL
);


CREATE INDEX actor_workstation_setting_workstation_idx 
    ON actor.workstation_setting (workstation);

CREATE OR REPLACE FUNCTION config.setting_is_user_or_ws()
RETURNS TRIGGER AS $FUNC$
BEGIN

    IF TG_TABLE_NAME = 'usr_setting_type' THEN
        PERFORM TRUE FROM config.workstation_setting_type cwst
            WHERE cwst.name = NEW.name;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'workstation_setting_type' THEN
        PERFORM TRUE FROM config.usr_setting_type cust
            WHERE cust.name = NEW.name;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    END IF;

    RAISE EXCEPTION 
        '% Cannot be used as both a user setting and a workstation setting.', 
        NEW.name;
END;
$FUNC$ LANGUAGE PLPGSQL STABLE;

CREATE CONSTRAINT TRIGGER check_setting_is_usr_or_ws
  AFTER INSERT OR UPDATE ON config.usr_setting_type
  FOR EACH ROW EXECUTE PROCEDURE config.setting_is_user_or_ws();

CREATE CONSTRAINT TRIGGER check_setting_is_usr_or_ws
  AFTER INSERT OR UPDATE ON config.workstation_setting_type
  FOR EACH ROW EXECUTE PROCEDURE config.setting_is_user_or_ws();

CREATE OR REPLACE FUNCTION actor.get_cascade_setting(
    setting_name TEXT, org_id INT, user_id INT, workstation_id INT) 
    RETURNS actor.cascade_setting_summary AS
$FUNC$
DECLARE
    setting_value JSON;
    summary actor.cascade_setting_summary;
    org_setting_type config.org_unit_setting_type%ROWTYPE;
BEGIN

    summary.name := setting_name;

    -- Collect the org setting type status first in case we exit early.
    -- The existance of an org setting type is not considered
    -- privileged information.
    SELECT INTO org_setting_type * 
        FROM config.org_unit_setting_type WHERE name = setting_name;
    IF FOUND THEN
        summary.has_org_setting := TRUE;
    ELSE
        summary.has_org_setting := FALSE;
    END IF;

    -- User and workstation settings have the same priority.
    -- Start with user settings since that's the simplest code path.
    -- The workstation_id is ignored if no user_id is provided.
    IF user_id IS NOT NULL THEN

        SELECT INTO summary.value value FROM actor.usr_setting
            WHERE usr = user_id AND name = setting_name;

        IF FOUND THEN
            -- if we have a value, we have a setting type
            summary.has_user_setting := TRUE;

            IF workstation_id IS NOT NULL THEN
                -- Only inform the caller about the workstation
                -- setting type disposition when a workstation id is
                -- provided.  Otherwise, it's NULL to indicate UNKNOWN.
                summary.has_workstation_setting := FALSE;
            END IF;

            RETURN summary;
        END IF;

        -- no user setting value, but a setting type may exist
        SELECT INTO summary.has_user_setting EXISTS (
            SELECT TRUE FROM config.usr_setting_type 
            WHERE name = setting_name
        );

        IF workstation_id IS NOT NULL THEN 

            IF NOT summary.has_user_setting THEN
                -- A workstation setting type may only exist when a user
                -- setting type does not.

                SELECT INTO summary.value value 
                    FROM actor.workstation_setting         
                    WHERE workstation = workstation_id AND name = setting_name;

                IF FOUND THEN
                    -- if we have a value, we have a setting type
                    summary.has_workstation_setting := TRUE;
                    RETURN summary;
                END IF;

                -- no value, but a setting type may exist
                SELECT INTO summary.has_workstation_setting EXISTS (
                    SELECT TRUE FROM config.workstation_setting_type 
                    WHERE name = setting_name
                );
            END IF;

            -- Finally make use of the workstation to determine the org
            -- unit if none is provided.
            IF org_id IS NULL AND summary.has_org_setting THEN
                SELECT INTO org_id owning_lib 
                    FROM actor.workstation WHERE id = workstation_id;
            END IF;
        END IF;
    END IF;

    -- Some org unit settings are protected by a view permission.
    -- First see if we have any data that needs protecting, then 
    -- check the permission if needed.

    IF NOT summary.has_org_setting THEN
        RETURN summary;
    END IF;

    -- avoid putting the value into the summary until we confirm
    -- the value should be visible to the caller.
    SELECT INTO setting_value value 
        FROM actor.org_unit_ancestor_setting(setting_name, org_id);

    IF NOT FOUND THEN
        -- No value found -- perm check is irrelevant.
        RETURN summary;
    END IF;

    IF org_setting_type.view_perm IS NOT NULL THEN

        IF user_id IS NULL THEN
            RAISE NOTICE 'Perm check required but no user_id provided';
            RETURN summary;
        END IF;

        IF NOT permission.usr_has_perm(
            user_id, (SELECT code FROM permission.perm_list 
                WHERE id = org_setting_type.view_perm), org_id) 
        THEN
            RAISE NOTICE 'Perm check failed for user % on %',
                user_id, org_setting_type.view_perm;
            RETURN summary;
        END IF;
    END IF;

    -- Perm check succeeded or was not necessary.
    summary.value := setting_value;
    RETURN summary;
END;
$FUNC$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION actor.get_cascade_setting_batch(
    setting_names TEXT[], org_id INT, user_id INT, workstation_id INT) 
    RETURNS SETOF actor.cascade_setting_summary AS
$FUNC$
-- Returns a row per setting matching the setting name order.  If no 
-- value is applied, NULL is returned to retain name-response ordering.
DECLARE
    setting_name TEXT;
    summary actor.cascade_setting_summary;
BEGIN
    FOREACH setting_name IN ARRAY setting_names LOOP
        SELECT INTO summary * FROM actor.get_cascade_setting(
            setting_Name, org_id, user_id, workstation_id);
        RETURN NEXT summary;
    END LOOP;
END;
$FUNC$ LANGUAGE PLPGSQL;





SELECT evergreen.upgrade_deps_block_check('1117', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES
 (608, 'APPLY_WORKSTATION_SETTING',
   oils_i18n_gettext(608, 'APPLY_WORKSTATION_SETTING', 'ppl', 'description'));

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.circ.checkin.no_precat_alert', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.no_precat_alert',
        'Checkin: Ignore Precataloged Items',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.noop', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.noop',
        'Checkin: Suppress Holds and Transits',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.void_overdues', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.void_overdues',
        'Checkin: Amnesty Mode',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.auto_print_holds_transits', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.auto_print_holds_transits',
        'Checkin: Auto-Print Holds and Transits',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.clear_expired', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.clear_expired',
        'Checkin: Clear Holds Shelf',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.retarget_holds', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.retarget_holds',
        'Checkin: Retarget Local Holds',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.retarget_holds_all', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.retarget_holds_all',
        'Checkin: Retarget All Statuses',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.hold_as_transit', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.hold_as_transit',
        'Checkin: Capture Local Holds as Transits',
        'cwst', 'label'
    )
), (
    'eg.circ.checkin.manual_float', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.checkin.manual_float',
        'Checkin: Manual Floating Active',
        'cwst', 'label'
    )
), (
    'eg.circ.patron.summary.collapse', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.summary.collapse',
        'Collaps Patron Summary Display',
        'cwst', 'label'
    )
), (
    'circ.bills.receiptonpay', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.bills.receiptonpay',
        'Print Receipt On Payment',
        'cwst', 'label'
    )
), (
    'circ.renew.strict_barcode', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.renew.strict_barcode',
        'Renew: Strict Barcode',
        'cwst', 'label'
    )
), (
    'circ.checkin.strict_barcode', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.checkin.strict_barcode',
        'Checkin: Strict Barcode',
        'cwst', 'label'
    )
), (
    'circ.checkout.strict_barcode', 'circ', 'bool',
    oils_i18n_gettext(
        'circ.checkout.strict_barcode',
        'Checkout: Strict Barcode',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_copies', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_copies',
        'Holdings View Show Copies',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_empty', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_empty',
        'Holdings View Show Empty Volumes',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_empty_org', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_empty_org',
        'Holdings View Show Empty Orgs',
        'cwst', 'label'
    )
), (
    'cat.holdings_show_vols', 'cat', 'bool',
    oils_i18n_gettext(
        'cat.holdings_show_vols',
        'Holdings View Show Volumes',
        'cwst', 'label'
    )
), (
    'cat.copy.defaults', 'cat', 'object',
    oils_i18n_gettext(
        'cat.copy.defaults',
        'Copy Edit Default Values',
        'cwst', 'label'
    )
), (
    'cat.printlabels.default_template', 'cat', 'string',
    oils_i18n_gettext(
        'cat.printlabels.default_template',
        'Print Label Default Template',
        'cwst', 'label'
    )
), (
    'cat.printlabels.templates', 'cat', 'object',
    oils_i18n_gettext(
        'cat.printlabels.templates',
        'Print Label Templates',
        'cwst', 'label'
    )
), (
    'eg.circ.patron.search.include_inactive', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.search.include_inactive',
        'Patron Search Include Inactive',
        'cwst', 'label'
    )
), (
    'eg.circ.patron.search.show_extras', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.search.show_extras',
        'Patron Search Show Extra Search Options',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.checkin.checkin', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.checkin.checkin',
        'Grid Config: circ.checkin.checkin',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.checkin.capture', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.checkin.capture',
        'Grid Config: circ.checkin.capture',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.copy_tag_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.copy_tag_type',
        'Grid Config: admin.server.config.copy_tag_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field_virtual_map.grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field_virtual_map.grid',
        'Grid Config: admin.server.config.metabib_field_virtual_map.grid',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.metabib_field.grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.metabib_field.grid',
        'Grid Config: admin.server.config.metabib_field.grid',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.marc_field', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.marc_field',
        'Grid Config: admin.server.config.marc_field',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.asset.copy_tag', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.asset.copy_tag',
        'Grid Config: admin.server.asset.copy_tag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.circ.neg_balance_users', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.circ.neg_balance_users',
        'Grid Config: admin.local.circ.neg_balance_users',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.rating.badge', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.rating.badge',
        'Grid Config: admin.local.rating.badge',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.workstation.work_log', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.workstation.work_log',
        'Grid Config: admin.workstation.work_log',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.workstation.patron_log', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.workstation.patron_log',
        'Grid Config: admin.workstation.patron_log',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.serials.pattern_template', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.serials.pattern_template',
        'Grid Config: admin.serials.pattern_template',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.copy_templates', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.copy_templates',
        'Grid Config: serials.copy_templates',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.record_overlay.holdings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.record_overlay.holdings',
        'Grid Config: cat.record_overlay.holdings',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.record.search', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.record.search',
        'Grid Config: cat.bucket.record.search',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.record.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.record.view',
        'Grid Config: cat.bucket.record.view',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.record.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.record.pending',
        'Grid Config: cat.bucket.record.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.copy.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.copy.view',
        'Grid Config: cat.bucket.copy.view',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.copy.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.copy.pending',
        'Grid Config: cat.bucket.copy.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.items', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.items',
        'Grid Config: cat.items',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.volcopy.copies', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.volcopy.copies',
        'Grid Config: cat.volcopy.copies',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.volcopy.copies.complete', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.volcopy.copies.complete',
        'Grid Config: cat.volcopy.copies.complete',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.peer_bibs', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.peer_bibs',
        'Grid Config: cat.peer_bibs',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.catalog.holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.catalog.holds',
        'Grid Config: cat.catalog.holds',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.holdings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.holdings',
        'Grid Config: cat.holdings',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.z3950_results', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.z3950_results',
        'Grid Config: cat.z3950_results',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.holds.shelf', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.holds.shelf',
        'Grid Config: circ.holds.shelf',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.holds.pull', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.holds.pull',
        'Grid Config: circ.holds.pull',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.in_house_use', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.in_house_use',
        'Grid Config: circ.in_house_use',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.renew', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.renew',
        'Grid Config: circ.renew',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.transits.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.transits.list',
        'Grid Config: circ.transits.list',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.holds',
        'Grid Config: circ.patron.holds',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.pending_patrons.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.pending_patrons.list',
        'Grid Config: circ.pending_patrons.list',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.items_out.noncat', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.items_out.noncat',
        'Grid Config: circ.patron.items_out.noncat',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.items_out', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.items_out',
        'Grid Config: circ.patron.items_out',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.billhistory_payments', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.billhistory_payments',
        'Grid Config: circ.patron.billhistory_payments',
        'cwst', 'label'
    )
), (
    'eg.grid.user.bucket.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.user.bucket.view',
        'Grid Config: user.bucket.view',
        'cwst', 'label'
    )
), (
    'eg.grid.user.bucket.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.user.bucket.pending',
        'Grid Config: user.bucket.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.staff_messages', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.staff_messages',
        'Grid Config: circ.patron.staff_messages',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.archived_messages', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.archived_messages',
        'Grid Config: circ.patron.archived_messages',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.bills', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.bills',
        'Grid Config: circ.patron.bills',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.checkout', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.checkout',
        'Grid Config: circ.patron.checkout',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.mfhd_grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.mfhd_grid',
        'Grid Config: serials.mfhd_grid',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.view_item_grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.view_item_grid',
        'Grid Config: serials.view_item_grid',
        'cwst', 'label'
    )
), (
    'eg.grid.serials.dist_stream_grid', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.serials.dist_stream_grid',
        'Grid Config: serials.dist_stream_grid',
        'cwst', 'label'
    )
), (
    'eg.grid.circ.patron.search', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.circ.patron.search',
        'Grid Config: circ.patron.search',
        'cwst', 'label'
    )
), (
    'eg.cat.record.summary.collapse', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.cat.record.summary.collapse',
        'Collapse Bib Record Summary',
        'cwst', 'label'
    )
), (
    'cat.marcedit.flateditor', 'gui', 'bool',
    oils_i18n_gettext(
        'cat.marcedit.flateditor',
        'Use Flat MARC Editor',
        'cwst', 'label'
    )
), (
    'cat.marcedit.stack_subfields', 'gui', 'bool',
    oils_i18n_gettext(
        'cat.marcedit.stack_subfields',
        'MARC Editor Stack Subfields',
        'cwst', 'label'
    )
), (
    'eg.offline.print_receipt', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.offline.print_receipt',
        'Offline Print Receipt',
        'cwst', 'label'
    )
), (
    'eg.offline.strict_barcode', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.offline.strict_barcode',
        'Offline Use Strict Barcode',
        'cwst', 'label'
    )
), (
    'cat.default_bib_marc_template', 'gui', 'string',
    oils_i18n_gettext(
        'cat.default_bib_marc_template',
        'Default MARC Template',
        'cwst', 'label'
    )
), (
    'eg.audio.disable', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.audio.disable',
        'Disable Staff Client Notification Audio',
        'cwst', 'label'
    )
), (
    'eg.search.adv_pane', 'gui', 'string',
    oils_i18n_gettext(
        'eg.search.adv_pane',
        'Catalog Advanced Search Default Pane',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.bills_current', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.bills_current',
        'Print Template Context: bills_current',
        'cwst', 'label'
    )
), (
    'eg.print.template.bills_current', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.bills_current',
        'Print Template: bills_current',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.bills_historical', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.bills_historical',
        'Print Template Context: bills_historical',
        'cwst', 'label'
    )
), (
    'eg.print.template.bills_historical', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.bills_historical',
        'Print Template: bills_historical',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.bill_payment', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.bill_payment',
        'Print Template Context: bill_payment',
        'cwst', 'label'
    )
), (
    'eg.print.template.bill_payment', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.bill_payment',
        'Print Template: bill_payment',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.checkin',
        'Print Template Context: checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template.checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.checkin',
        'Print Template: checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.checkout',
        'Print Template Context: checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template.checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.checkout',
        'Print Template: checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_transit_slip',
        'Print Template Context: hold_transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_transit_slip',
        'Print Template: hold_transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_shelf_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_shelf_slip',
        'Print Template Context: hold_shelf_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_shelf_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_shelf_slip',
        'Print Template: hold_shelf_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.holds_for_bib', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.holds_for_bib',
        'Print Template Context: holds_for_bib',
        'cwst', 'label'
    )
), (
    'eg.print.template.holds_for_bib', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.holds_for_bib',
        'Print Template: holds_for_bib',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.holds_for_patron', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.holds_for_patron',
        'Print Template Context: holds_for_patron',
        'cwst', 'label'
    )
), (
    'eg.print.template.holds_for_patron', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.holds_for_patron',
        'Print Template: holds_for_patron',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_pull_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_pull_list',
        'Print Template Context: hold_pull_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_pull_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_pull_list',
        'Print Template: hold_pull_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.hold_shelf_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.hold_shelf_list',
        'Print Template Context: hold_shelf_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.hold_shelf_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.hold_shelf_list',
        'Print Template: hold_shelf_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.in_house_use_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.in_house_use_list',
        'Print Template Context: in_house_use_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.in_house_use_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.in_house_use_list',
        'Print Template: in_house_use_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.item_status', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.item_status',
        'Print Template Context: item_status',
        'cwst', 'label'
    )
), (
    'eg.print.template.item_status', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.item_status',
        'Print Template: item_status',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.items_out', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.items_out',
        'Print Template Context: items_out',
        'cwst', 'label'
    )
), (
    'eg.print.template.items_out', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.items_out',
        'Print Template: items_out',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.patron_address', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.patron_address',
        'Print Template Context: patron_address',
        'cwst', 'label'
    )
), (
    'eg.print.template.patron_address', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.patron_address',
        'Print Template: patron_address',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.patron_data', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.patron_data',
        'Print Template Context: patron_data',
        'cwst', 'label'
    )
), (
    'eg.print.template.patron_data', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.patron_data',
        'Print Template: patron_data',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.patron_note', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.patron_note',
        'Print Template Context: patron_note',
        'cwst', 'label'
    )
), (
    'eg.print.template.patron_note', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.patron_note',
        'Print Template: patron_note',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.renew',
        'Print Template Context: renew',
        'cwst', 'label'
    )
), (
    'eg.print.template.renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.renew',
        'Print Template: renew',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.transit_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.transit_list',
        'Print Template Context: transit_list',
        'cwst', 'label'
    )
), (
    'eg.print.template.transit_list', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.transit_list',
        'Print Template: transit_list',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.transit_slip',
        'Print Template Context: transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template.transit_slip', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.transit_slip',
        'Print Template: transit_slip',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_checkout',
        'Print Template Context: offline_checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_checkout', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_checkout',
        'Print Template: offline_checkout',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_renew',
        'Print Template Context: offline_renew',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_renew', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_renew',
        'Print Template: offline_renew',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_checkin',
        'Print Template Context: offline_checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_checkin', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_checkin',
        'Print Template: offline_checkin',
        'cwst', 'label'
    )
), (
    'eg.print.template_context.offline_in_house_use', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.offline_in_house_use',
        'Print Template Context: offline_in_house_use',
        'cwst', 'label'
    )
), (
    'eg.print.template.offline_in_house_use', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template.offline_in_house_use',
        'Print Template: offline_in_house_use',
        'cwst', 'label'
    )
), (
    'eg.serials.stream_names', 'gui', 'array',
    oils_i18n_gettext(
        'eg.serials.stream_names',
        'Serials Local Stream Names',
        'cwst', 'label'
    )
), (
    'eg.serials.items.do_print_routing_lists', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.serials.items.do_print_routing_lists',
        'Serials Print Routing Lists',
        'cwst', 'label'
    )
), (
    'eg.serials.items.receive_and_barcode', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.serials.items.receive_and_barcode',
        'Serials Barcode On Receive',
        'cwst', 'label'
    )
);


-- More values with fm_class'es
INSERT INTO config.workstation_setting_type (name, grp, datatype, fm_class, label)
VALUES (
    'eg.search.search_lib', 'gui', 'link', 'aou',
    oils_i18n_gettext(
        'eg.search.search_lib',
        'Staff Catalog Default Search Library',
        'cwst', 'label'
    )
), (
    'eg.search.pref_lib', 'gui', 'link', 'aou',
    oils_i18n_gettext(
        'eg.search.pref_lib',
        'Staff Catalog Preferred Library',
        'cwst', 'label'
    )
);





SELECT evergreen.upgrade_deps_block_check('1118', :eg_version);

UPDATE action_trigger.event_definition
SET template =
$$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Bibliographic Records
Auto-Submitted: auto-generated

[% FOR cbreb IN target %]
[% FOR item IN cbreb.items;
    bre_id = item.target_biblio_record_entry;

    bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
    title = '';
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;

    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
    publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
    pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
    isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
    issn = bibxml.findnodes('//*[@tag="022"]/*[@code="a"]').textContent;
    upc = bibxml.findnodes('//*[@tag="024"]/*[@code="a"]').textContent;
%]

[% loop.count %]/[% loop.size %].  Bib ID# [% bre_id %] 
[% IF isbn %]ISBN: [% isbn _ "\n" %][% END -%]
[% IF issn %]ISSN: [% issn _ "\n" %][% END -%]
[% IF upc  %]UPC:  [% upc _ "\n" %] [% END -%]
Title: [% title %]
Author: [% author %]
Publication Info: [% publisher %] [% pubdate %]
Item Type: [% item_type %]

[% END %]
[% END %]
$$
WHERE hook = 'biblio.format.record_entry.email'
-- from previous stock definition
AND MD5(template) = 'ee4e6c1b3049086c570c7a77413d46c1';

UPDATE action_trigger.event_definition
SET template =
$$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR item IN cbreb.items;
        bre_id = item.target_biblio_record_entry;

        bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
        title = '';
        FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
            title = title _ part.textContent;
        END;

        author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
        item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
        publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
        pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
        isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
        %]

        <li>
            Bib ID# [% bre_id %] ISBN: [% isbn %]<br />
            Title: [% title %]<br />
            Author: [% author %]<br />
            Publication Info: [% publisher %] [% pubdate %]<br/>
            Item Type: [% item_type %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$
WHERE hook = 'biblio.format.record_entry.print'
-- from previous stock definition
AND MD5(template) = '9ada7ea8417cb23f89d0dc8f15ec68d0';


SELECT evergreen.upgrade_deps_block_check('1120', :eg_version);

--Only insert if the attributes are not already present

INSERT INTO config.z3950_attr (source, name, label, code, format, truncation)
SELECT 'oclc','upc','UPC','1007','6','0'
WHERE NOT EXISTS (SELECT name FROM config.z3950_attr WHERE source = 'oclc' AND name = 'upc');

INSERT INTO config.z3950_attr (source, name, label, code, format, truncation)
SELECT 'loc','upc','UPC','1007','1','1'
WHERE NOT EXISTS (SELECT name FROM config.z3950_attr WHERE source = 'loc' AND name = 'upc');

SELECT evergreen.upgrade_deps_block_check('1121', :eg_version);

CREATE TABLE permission.grp_tree_display_entry (
    id      SERIAL PRIMARY KEY,
    position INTEGER NOT NULL,
    org     INTEGER NOT NULL REFERENCES actor.org_unit (id)
            DEFERRABLE INITIALLY DEFERRED,
    grp     INTEGER NOT NULL REFERENCES permission.grp_tree (id)
            DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT pgtde_once_per_org UNIQUE (org, grp)
);

ALTER TABLE permission.grp_tree_display_entry
    ADD COLUMN parent integer REFERENCES permission.grp_tree_display_entry (id)
            DEFERRABLE INITIALLY DEFERRED;

INSERT INTO permission.perm_list (id, code, description)
VALUES (609, 'MANAGE_CUSTOM_PERM_GRP_TREE', oils_i18n_gettext( 609,
    'Allows a user to manage custom permission group lists.', 'ppl', 'description' ));
            

SELECT evergreen.upgrade_deps_block_check('1122', :eg_version);

ALTER TABLE actor.usr 
    ADD COLUMN pref_prefix TEXT,
    ADD COLUMN pref_first_given_name TEXT,
    ADD COLUMN pref_second_given_name TEXT,
    ADD COLUMN pref_family_name TEXT,
    ADD COLUMN pref_suffix TEXT,
    ADD COLUMN name_keywords TEXT,
    ADD COLUMN name_kw_tsvector TSVECTOR;

ALTER TABLE staging.user_stage
    ADD COLUMN pref_first_given_name TEXT,
    ADD COLUMN pref_second_given_name TEXT,
    ADD COLUMN pref_family_name TEXT;

CREATE INDEX actor_usr_pref_first_given_name_idx 
    ON actor.usr (evergreen.lowercase(pref_first_given_name));
CREATE INDEX actor_usr_pref_second_given_name_idx 
    ON actor.usr (evergreen.lowercase(pref_second_given_name));
CREATE INDEX actor_usr_pref_family_name_idx 
    ON actor.usr (evergreen.lowercase(pref_family_name));
CREATE INDEX actor_usr_pref_first_given_name_unaccent_idx 
    ON actor.usr (evergreen.unaccent_and_squash(pref_first_given_name));
CREATE INDEX actor_usr_pref_second_given_name_unaccent_idx 
    ON actor.usr (evergreen.unaccent_and_squash(pref_second_given_name));
CREATE INDEX actor_usr_pref_family_name_unaccent_idx 
   ON actor.usr (evergreen.unaccent_and_squash(pref_family_name));

-- Update keyword indexes for existing patrons

UPDATE actor.usr SET name_kw_tsvector = 
    TO_TSVECTOR(
        COALESCE(prefix, '') || ' ' || 
        COALESCE(first_given_name, '') || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(first_given_name), '') || ' ' || 
        COALESCE(second_given_name, '') || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(second_given_name), '') || ' ' || 
        COALESCE(family_name, '') || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(family_name), '') || ' ' || 
        COALESCE(suffix, '')
    );

CREATE OR REPLACE FUNCTION actor.user_ingest_name_keywords() 
    RETURNS TRIGGER AS $func$
BEGIN
    NEW.name_kw_tsvector := TO_TSVECTOR(
        COALESCE(NEW.prefix, '')                || ' ' || 
        COALESCE(NEW.first_given_name, '')      || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.first_given_name), '') || ' ' || 
        COALESCE(NEW.second_given_name, '')     || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.second_given_name), '') || ' ' || 
        COALESCE(NEW.family_name, '')           || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.family_name), '') || ' ' || 
        COALESCE(NEW.suffix, '')                || ' ' || 
        COALESCE(NEW.pref_prefix, '')            || ' ' || 
        COALESCE(NEW.pref_first_given_name, '')  || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_first_given_name), '') || ' ' || 
        COALESCE(NEW.pref_second_given_name, '') || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_second_given_name), '') || ' ' || 
        COALESCE(NEW.pref_family_name, '')       || ' ' || 
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_family_name), '') || ' ' || 
        COALESCE(NEW.pref_suffix, '')            || ' ' || 
        COALESCE(NEW.name_keywords, '')
    );
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

-- Add after the batch upate above to avoid duplicate updates.
CREATE TRIGGER user_ingest_name_keywords_tgr 
    BEFORE INSERT OR UPDATE ON actor.usr 
    FOR EACH ROW EXECUTE PROCEDURE actor.user_ingest_name_keywords();


-- merge pref names from source user to target user, except when
-- clobbering existing pref names.
CREATE OR REPLACE FUNCTION actor.usr_merge(src_usr INT, dest_usr INT, 
    del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) 
    RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- propagate preferred name values from the source user to the
    -- destination user, but only when values are not being replaced.
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr)
    UPDATE actor.usr SET 
        pref_prefix = 
            COALESCE(pref_prefix, (SELECT pref_prefix FROM susr)),
        pref_first_given_name = 
            COALESCE(pref_first_given_name, (SELECT pref_first_given_name FROM susr)),
        pref_second_given_name = 
            COALESCE(pref_second_given_name, (SELECT pref_second_given_name FROM susr)),
        pref_family_name = 
            COALESCE(pref_family_name, (SELECT pref_family_name FROM susr)),
        pref_suffix = 
            COALESCE(pref_suffix, (SELECT pref_suffix FROM susr))
    WHERE id = dest_usr;

    -- Copy and deduplicate name keywords
    -- String -> array -> rows -> DISTINCT -> array -> string
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr),
         dusr AS (SELECT * FROM actor.usr WHERE id = dest_usr)
    UPDATE actor.usr SET name_keywords = (
        WITH keywords AS (
            SELECT DISTINCT UNNEST(
                REGEXP_SPLIT_TO_ARRAY(
                    COALESCE((SELECT name_keywords FROM susr), '') || ' ' ||
                    COALESCE((SELECT name_keywords FROM dusr), ''),  E'\\s+'
                )
            ) AS parts
        ) SELECT ARRAY_TO_STRING(ARRAY_AGG(kw.parts), ' ') FROM keywords kw
    ) WHERE id = dest_usr;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;




SELECT evergreen.upgrade_deps_block_check('1123', :eg_version);

    ALTER TABLE config.rule_circ_duration
    ADD column max_auto_renewals INTEGER;

    ALTER TABLE action.circulation
    ADD column auto_renewal BOOLEAN;

    ALTER TABLE action.circulation
    ADD column auto_renewal_remaining INTEGER;

    ALTER TABLE action.aged_circulation
    ADD column auto_renewal BOOLEAN;

    ALTER TABLE action.aged_circulation
    ADD column auto_renewal_remaining INTEGER;

    INSERT INTO action_trigger.validator values('CircIsAutoRenewable', 'Checks whether the circulation is able to be autorenewed.');
    INSERT INTO action_trigger.reactor values('Circ::AutoRenew', 'Auto-Renews a circulation.');
    INSERT INTO action_trigger.hook(key, core_type, description) values('autorenewal', 'circ', 'Item was auto-renewed to patron.');

    -- AutoRenewer A/T Def: 
    INSERT INTO action_trigger.event_definition(active, owner, name, hook, validator, reactor, delay, max_delay, delay_field, group_field)
        values (false, 1, 'Autorenew', 'checkout.due', 'CircIsOpen', 'Circ::AutoRenew', '-23 hours'::interval,'-1 minute'::interval, 'due_date', 'usr');

    -- AutoRenewal outcome Email notifier A/T Def:
    INSERT INTO action_trigger.event_definition(active, owner, name, hook, validator, reactor, group_field, template)
        values (false, 1, 'AutorenewNotify', 'autorenewal', 'NOOP_True', 'SendEmail', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Items Out Auto-Renewal Notification 
Auto-Submitted: auto-generated

Dear [% user.family_name %], [% user.first_given_name %]
An automatic renewal attempt was made for the following items:

[% FOR circ IN target %]
    [%- SET idx = loop.count - 1; SET udata =  user_data.$idx -%]
    [%- SET cid = circ.target_copy || udata.copy -%]
    [%- SET copy_details = helpers.get_copy_bib_basics(cid) -%]
    Item# [% loop.count %]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    [%- IF udata.is_renewed %]
    Status: Loan Renewed
    New Due Date: [% date.format(helpers.format_date(udata.new_due_date), '%Y-%m-%d') %]
    [%- ELSE %]
    Status: Not Renewed
    Reason: [% udata.reason %]
    Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    [% END %]
[% END %]
$$
    );

    INSERT INTO action_trigger.environment (event_def, path ) VALUES
    ( currval('action_trigger.event_definition_id_seq'), 'usr' ),
    ( currval('action_trigger.event_definition_id_seq'), 'circ_lib' );


DROP VIEW action.all_circulation;
CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining, NULL AS usr
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, circ.copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ, circ.auto_renewal, circ.auto_renewal_remaining, circ.usr
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);


DROP FUNCTION action.summarize_all_circ_chain (INTEGER);
DROP FUNCTION action.all_circ_chain (INTEGER);

-- rebuild slim circ view
DROP VIEW action.all_circulation_slim;
CREATE OR REPLACE VIEW action.all_circulation_slim AS
    SELECT
        id,
        usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        auto_renewal,
        auto_renewal_remaining,
        parent_circ
    FROM action.circulation
UNION ALL
    SELECT
        id,
        NULL AS usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        auto_renewal,
        auto_renewal_remaining,
        parent_circ
    FROM action.aged_circulation
;

CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation_slim AS $$
DECLARE
    tmp_circ action.all_circulation_slim%ROWTYPE;
    circ_0 action.all_circulation_slim%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation_slim WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- same as action.summarize_circ_chain, but returns data collected
-- from action.all_circulation, which may include aged circulations.
CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation_slim%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation_slim%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation_slim%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.all_circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';



SELECT evergreen.upgrade_deps_block_check('1124', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.wide_holds.shelf', 'gui', 'object',
    oils_i18n_gettext (
        'eg.grid.circ.wide_holds.shelf',
        'Grid Config: circ.wide_holds.shelf',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.catalog.wide_holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.catalog.wide_holds',
        'Grid Config: cat.catalog.wide_holds',
        'cwst', 'label'
    )
);

DELETE from config.workstation_setting_type
WHERE name = 'eg.grid.cat.catalog.holds' OR name = 'eg.grid.circ.holds.shelf';


SELECT evergreen.upgrade_deps_block_check('1125', :eg_version);

CREATE TABLE asset.latest_inventory (
    id                          SERIAL                      PRIMARY KEY,
    inventory_workstation       INTEGER                     REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
    inventory_date              TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
    copy                        BIGINT                      NOT NULL
);
CREATE INDEX latest_inventory_copy_idx ON asset.latest_inventory (copy);

CREATE OR REPLACE FUNCTION evergreen.asset_latest_inventory_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, copy:%s$$, NEW.copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_asset_latest_inventory_copy_fkey
        AFTER UPDATE OR INSERT ON asset.latest_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_latest_inventory_copy_inh_fkey();

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.circ.checkin.do_inventory_update', 'circ', 'bool',
    oils_i18n_gettext (
             'eg.circ.checkin.do_inventory_update',
             'Checkin: Update Inventory',
             'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1126', :eg_version);

CREATE TABLE vandelay.session_tracker (
    id          BIGSERIAL PRIMARY KEY,

    -- string of characters (e.g. md5) used for linking trackers
    -- of different actions into a series.  There can be multiple
    -- session_keys of each action type, creating the opportunity
    -- to link multiple action trackers into a single session.
    session_key TEXT NOT NULL,

    -- optional user-supplied name
    name        TEXT NOT NULL, 

    usr         INTEGER NOT NULL REFERENCES actor.usr(id)
                DEFERRABLE INITIALLY DEFERRED,

    -- org unit can be derived from WS
    workstation INTEGER NOT NULL REFERENCES actor.workstation(id)
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,

    -- bib/auth
    record_type vandelay.bib_queue_queue_type NOT NULL DEFAULT 'bib',

    -- Queue defines the source of the data, it does not necessarily
    -- mean that an action is being performed against an entire queue.
    -- E.g. some imports are misc. lists of record IDs, but they always 
    -- come from one queue.
    -- No foreign key -- could be auth or bib queue.
    queue       BIGINT NOT NULL,

    create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    update_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    state       TEXT NOT NULL DEFAULT 'active',

    action_type TEXT NOT NULL DEFAULT 'enqueue', -- import

    -- total number of tasks to perform / loosely defined
    -- could be # of recs to import or # of recs + # of copies 
    -- depending on the import context
    total_actions INTEGER NOT NULL DEFAULT 0,

    -- total number of tasked performed so far
    actions_performed INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT vand_tracker_valid_state 
        CHECK (state IN ('active','error','complete')),

    CONSTRAINT vand_tracker_valid_action_type
        CHECK (action_type IN ('upload', 'enqueue', 'import'))
);


CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- propagate preferred name values from the source user to the
    -- destination user, but only when values are not being replaced.
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr)
    UPDATE actor.usr SET 
        pref_prefix = 
            COALESCE(pref_prefix, (SELECT pref_prefix FROM susr)),
        pref_first_given_name = 
            COALESCE(pref_first_given_name, (SELECT pref_first_given_name FROM susr)),
        pref_second_given_name = 
            COALESCE(pref_second_given_name, (SELECT pref_second_given_name FROM susr)),
        pref_family_name = 
            COALESCE(pref_family_name, (SELECT pref_family_name FROM susr)),
        pref_suffix = 
            COALESCE(pref_suffix, (SELECT pref_suffix FROM susr))
    WHERE id = dest_usr;

    -- Copy and deduplicate name keywords
    -- String -> array -> rows -> DISTINCT -> array -> string
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr),
         dusr AS (SELECT * FROM actor.usr WHERE id = dest_usr)
    UPDATE actor.usr SET name_keywords = (
        WITH keywords AS (
            SELECT DISTINCT UNNEST(
                REGEXP_SPLIT_TO_ARRAY(
                    COALESCE((SELECT name_keywords FROM susr), '') || ' ' ||
                    COALESCE((SELECT name_keywords FROM dusr), ''),  E'\\s+'
                )
            ) AS parts
        ) SELECT ARRAY_TO_STRING(ARRAY_AGG(kw.parts), ' ') FROM keywords kw
    ) WHERE id = dest_usr;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_note WHERE usr = src_usr;
	UPDATE actor.usr_note SET creator = dest_usr WHERE creator = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;



SELECT evergreen.upgrade_deps_block_check('1127', :eg_version);

ALTER TABLE acq.user_request ADD COLUMN cancel_time TIMESTAMPTZ;
ALTER TABLE acq.user_request ADD COLUMN upc TEXT;
ALTER TABLE action.hold_request ADD COLUMN acq_request INT REFERENCES acq.user_request (id);

UPDATE
    config.org_unit_setting_type
SET
    label = oils_i18n_gettext(
        'circ.holds.canceled.display_age',
        'Canceled holds/requests display age',
        'coust', 'label'),
    description = oils_i18n_gettext(
        'circ.holds.canceled.display_age',
        'Show all canceled entries in patron holds and patron acquisition requests interfaces that were canceled within this amount of time',
        'coust', 'description')
WHERE
    name = 'circ.holds.canceled.display_age'
;

UPDATE
    config.org_unit_setting_type
SET
    label = oils_i18n_gettext(
        'circ.holds.canceled.display_count',
        'Canceled holds/requests display count',
        'coust', 'label'),
    description = oils_i18n_gettext(
        'circ.holds.canceled.display_count',
        'How many canceled entries to show in patron holds and patron acquisition requests interfaces',
        'coust', 'description')
WHERE
    name = 'circ.holds.canceled.display_count'
;

INSERT INTO acq.cancel_reason (org_unit, keep_debits, id, label, description)
    VALUES (
        1, 'f', 1015,
        oils_i18n_gettext(1015, 'Canceled: Fulfilled', 'acqcr', 'label'),
        oils_i18n_gettext(1015, 'This acquisition request has been fulfilled.', 'acqcr', 'description')
    )
;

UPDATE
    acq.user_request_type
SET
    label = oils_i18n_gettext('2', 'Articles', 'aurt', 'label')
WHERE
    id = 2
;

INSERT INTO acq.user_request_type (id,label)
    SELECT 6, oils_i18n_gettext('6', 'Other', 'aurt', 'label');

SELECT SETVAL('acq.user_request_type_id_seq'::TEXT, (SELECT MAX(id)+1 FROM acq.user_request_type));

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 610, 'CLEAR_PURCHASE_REQUEST', oils_i18n_gettext(610,
    'Clear Completed User Purchase Requests', 'ppl', 'description'))
;

CREATE TABLE acq.user_request_status_type (
     id  SERIAL  PRIMARY KEY
    ,label TEXT
);

INSERT INTO acq.user_request_status_type (id,label) VALUES
     (0,oils_i18n_gettext(0,'Error','aurst','label'))
    ,(1,oils_i18n_gettext(1,'New','aurst','label'))
    ,(2,oils_i18n_gettext(2,'Pending','aurst','label'))
    ,(3,oils_i18n_gettext(3,'Ordered, Hold Not Placed','aurst','label'))
    ,(4,oils_i18n_gettext(4,'Ordered, Hold Placed','aurst','label'))
    ,(5,oils_i18n_gettext(5,'Received','aurst','label'))
    ,(6,oils_i18n_gettext(6,'Fulfilled','aurst','label'))
    ,(7,oils_i18n_gettext(7,'Canceled','aurst','label'))
;

SELECT SETVAL('acq.user_request_status_type_id_seq'::TEXT, 100);

-- not used
DELETE FROM actor.org_unit_setting WHERE name = 'acq.holds.allow_holds_from_purchase_request';
DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'acq.holds.allow_holds_from_purchase_request';
DELETE FROM config.org_unit_setting_type WHERE name = 'acq.holds.allow_holds_from_purchase_request';


SELECT evergreen.upgrade_deps_block_check('1128', :eg_version);

DROP VIEW auditor.acq_invoice_lifecycle;

ALTER TABLE acq.invoice
    ADD COLUMN close_date TIMESTAMPTZ,
    ADD COLUMN closed_by  INTEGER 
        REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;

-- duplicate steps for auditor table
ALTER TABLE auditor.acq_invoice_history
    ADD COLUMN close_date TIMESTAMPTZ,
    ADD COLUMN closed_by  INTEGER;

UPDATE acq.invoice SET close_date = NOW() WHERE complete;
UPDATE auditor.acq_invoice_history SET close_date = NOW() WHERE complete;

ALTER TABLE acq.invoice DROP COLUMN complete;
ALTER TABLE auditor.acq_invoice_history DROP COLUMN complete;

-- this recreates auditor.acq_invoice_lifecycle;
SELECT auditor.update_auditors();

CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_note WHERE usr = src_usr;
	UPDATE actor.usr_note SET creator = dest_usr WHERE creator = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;





-- UNDO (minus user purge/merge changes)
/*

DROP VIEW auditor.acq_invoice_lifecycle;
ALTER TABLE acq.invoice ADD COLUMN complete BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE auditor.acq_invoice_history 
    ADD COLUMN complete BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE acq.invoice SET complete = TRUE where close_date IS NOT NULL;
UPDATE auditor.acq_invoice_history 
    SET complete = TRUE where close_date IS NOT NULL;
SET CONSTRAINTS ALL IMMEDIATE; -- or get pending triggers error.
ALTER TABLE acq.invoice DROP COLUMN close_date, DROP COLUMN closed_by;
ALTER TABLE auditor.acq_invoice_history
    DROP COLUMN close_date, DROP COLUMN closed_by;
SELECT auditor.update_auditors();

*/


SELECT evergreen.upgrade_deps_block_check('1129', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.cancel_reason', 'gui', 'object',
    oils_i18n_gettext (
        'eg.grid.admin.acq.cancel_reason',
        'Grid Config: admin.acq.cancel_reason',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_event_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_event_type',
        'Grid Config: admin.acq.claim_event_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_policy', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_policy',
        'Grid Config: admin.acq.claim_policy',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_policy_action', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_policy_action',
        'Grid Config: admin.acq.claim_policy_action',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_type',
        'Grid Config: admin.acq.claim_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.currency_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.currency_type',
        'Grid Config: admin.acq.currency_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.edi_account', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.edi_account',
        'Grid Config: admin.acq.edi_account',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.edi_message', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.edi_message',
        'Grid Config: admin.acq.edi_message',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.exchange_rate', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.exchange_rate',
        'Grid Config: admin.acq.exchange_rate',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.fund_tag', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.fund_tag',
        'Grid Config: admin.acq.fund_tag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.invoice_item_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.invoice_item_type',
        'Grid Config: admin.acq.invoice_item_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.invoice_payment_method', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.invoice_payment_method',
        'Grid Config: admin.acq.invoice_payment_method',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.lineitem_alert_text', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.lineitem_alert_text',
        'Grid Config: admin.acq.lineitem_alert_text',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.lineitem_marc_attr_definition', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.lineitem_marc_attr_definition',
        'Grid Config: admin.acq.lineitem_marc_attr_definition',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1130', :eg_version);

CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- Bail if src_usr equals dest_usr because the result of merging a
    -- user with itself is not what you want.
    IF src_usr = dest_usr THEN
        RETURN;
    END IF;

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- propagate preferred name values from the source user to the
    -- destination user, but only when values are not being replaced.
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr)
    UPDATE actor.usr SET 
        pref_prefix = 
            COALESCE(pref_prefix, (SELECT pref_prefix FROM susr)),
        pref_first_given_name = 
            COALESCE(pref_first_given_name, (SELECT pref_first_given_name FROM susr)),
        pref_second_given_name = 
            COALESCE(pref_second_given_name, (SELECT pref_second_given_name FROM susr)),
        pref_family_name = 
            COALESCE(pref_family_name, (SELECT pref_family_name FROM susr)),
        pref_suffix = 
            COALESCE(pref_suffix, (SELECT pref_suffix FROM susr))
    WHERE id = dest_usr;

    -- Copy and deduplicate name keywords
    -- String -> array -> rows -> DISTINCT -> array -> string
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr),
         dusr AS (SELECT * FROM actor.usr WHERE id = dest_usr)
    UPDATE actor.usr SET name_keywords = (
        WITH keywords AS (
            SELECT DISTINCT UNNEST(
                REGEXP_SPLIT_TO_ARRAY(
                    COALESCE((SELECT name_keywords FROM susr), '') || ' ' ||
                    COALESCE((SELECT name_keywords FROM dusr), ''),  E'\\s+'
                )
            ) AS parts
        ) SELECT ARRAY_TO_STRING(ARRAY_AGG(kw.parts), ' ') FROM keywords kw
    ) WHERE id = dest_usr;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1131', :eg_version);

CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- Bail if src_usr equals dest_usr because the result of merging a
    -- user with itself is not what you want.
    IF src_usr = dest_usr THEN
        RETURN;
    END IF;

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- propagate preferred name values from the source user to the
    -- destination user, but only when values are not being replaced.
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr)
    UPDATE actor.usr SET 
        pref_prefix = 
            COALESCE(pref_prefix, (SELECT pref_prefix FROM susr)),
        pref_first_given_name = 
            COALESCE(pref_first_given_name, (SELECT pref_first_given_name FROM susr)),
        pref_second_given_name = 
            COALESCE(pref_second_given_name, (SELECT pref_second_given_name FROM susr)),
        pref_family_name = 
            COALESCE(pref_family_name, (SELECT pref_family_name FROM susr)),
        pref_suffix = 
            COALESCE(pref_suffix, (SELECT pref_suffix FROM susr))
    WHERE id = dest_usr;

    -- Copy and deduplicate name keywords
    -- String -> array -> rows -> DISTINCT -> array -> string
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr),
         dusr AS (SELECT * FROM actor.usr WHERE id = dest_usr)
    UPDATE actor.usr SET name_keywords = (
        WITH keywords AS (
            SELECT DISTINCT UNNEST(
                REGEXP_SPLIT_TO_ARRAY(
                    COALESCE((SELECT name_keywords FROM susr), '') || ' ' ||
                    COALESCE((SELECT name_keywords FROM dusr), ''),  E'\\s+'
                )
            ) AS parts
        ) SELECT ARRAY_TO_STRING(ARRAY_AGG(kw.parts), ' ') FROM keywords kw
    ) WHERE id = dest_usr;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1132', :eg_version); -- remingtron/csharp

-- fix two typo/pasto's in setting descriptions
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'circ.copy_alerts.forgive_fines_on_long_overdue_checkin',
	'Controls whether fines are automatically forgiven when checking out an '||
	'item that has been marked as long-overdue, and the corresponding copy alert has been '||
	'suppressed.',
	'coust', 'description'
)
WHERE NAME = 'circ.copy_alerts.forgive_fines_on_long_overdue_checkin';

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'circ.longoverdue.xact_open_on_zero',
	'Leave transaction open when long-overdue balance equals zero.  ' ||
	'This leaves the long-overdue copy on the patron record when it is paid',
	'coust', 'description'
)
WHERE NAME = 'circ.longoverdue.xact_open_on_zero';



SELECT evergreen.upgrade_deps_block_check('1133', :eg_version);

/* 
Unique indexes are not inherited by child tables, so they will not prevent
duplicate inserts on action.transit_copy and action.hold_transit_copy,
for example.  Use check constraints instead to enforce unique-per-copy
transits accross all transit types.
*/

-- Create an index for speedy check constraint lookups.
CREATE INDEX active_transit_for_copy 
    ON action.transit_copy (target_copy)
    WHERE dest_recv_time IS NULL AND cancel_time IS NULL;

-- Check for duplicate transits across all transit types
CREATE OR REPLACE FUNCTION action.copy_transit_is_unique() 
    RETURNS TRIGGER AS $func$
BEGIN
    PERFORM * FROM action.transit_copy 
        WHERE target_copy = NEW.target_copy 
              AND dest_recv_time IS NULL 
              AND cancel_time IS NULL;
    IF FOUND THEN
        RAISE EXCEPTION 'Copy id=% is already in transit', NEW.target_copy;
    END IF;
    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL STABLE;

-- Apply constraint to all transit tables
CREATE CONSTRAINT TRIGGER transit_copy_is_unique_check
    AFTER INSERT ON action.transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

CREATE CONSTRAINT TRIGGER hold_transit_copy_is_unique_check
    AFTER INSERT ON action.hold_transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

CREATE CONSTRAINT TRIGGER reservation_transit_copy_is_unique_check
    AFTER INSERT ON action.reservation_transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

/*
-- UNDO
DROP TRIGGER transit_copy_is_unique_check ON action.transit_copy;
DROP TRIGGER hold_transit_copy_is_unique_check ON action.hold_transit_copy;
DROP TRIGGER reservation_transit_copy_is_unique_check ON action.reservation_transit_copy;
DROP INDEX action.active_transit_for_copy;
*/


COMMIT;

\qecho A unique constraint was applied to action.transit_copy.  This will
\qecho only effect newly created transits.  Admins are encouraged to manually 
\qecho remove any existing duplicate transits by applying values for cancel_time
\qecho or dest_recv_time, or by deleting the offending transits. Below is a
\qecho query to locate duplicate transits.  Note dupes may exist accross
\qecho parent (action.transit_copy) and child tables (action.hold_transit_copy,
\qecho action.reservation_transit_copy)
\qecho 
\qecho    WITH dupe_transits AS (
\qecho        SELECT COUNT(*), target_copy FROM action.transit_copy
\qecho        WHERE dest_recv_time IS NULL AND cancel_time IS NULL
\qecho        GROUP BY 2 HAVING COUNT(*) > 1
\qecho    ) SELECT atc.* 
\qecho        FROM dupe_transits
\qecho        JOIN action.transit_copy atc USING (target_copy)
\qecho        WHERE dest_recv_time IS NULL AND cancel_time IS NULL;
\qecho

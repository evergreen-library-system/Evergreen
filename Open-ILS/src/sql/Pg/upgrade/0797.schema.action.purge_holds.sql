BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('0797', :eg_version); -- tsbere/Dyrcona/dbwells

-- New global flags for the purge function
INSERT INTO config.global_flag  (name, label, enabled)
    VALUES (
        'history.hold.retention_age',
        oils_i18n_gettext('history.hold.retention_age', 'Historical Hold Retention Age', 'cgf', 'label'),
        TRUE
    ),(
        'history.hold.retention_age_fulfilled',
        oils_i18n_gettext('history.hold.retention_age_fulfilled', 'Historical Hold Retention Age - Fulfilled', 'cgf', 'label'),
        FALSE
    ),(
        'history.hold.retention_age_canceled',
        oils_i18n_gettext('history.hold.retention_age_canceled', 'Historical Hold Retention Age - Canceled (Default)', 'cgf', 'label'),
        FALSE
    ),(
        'history.hold.retention_age_canceled_1',
        oils_i18n_gettext('history.hold.retention_age_canceled_1', 'Historical Hold Retention Age - Canceled (Untarged expiration)', 'cgf', 'label'),
        FALSE
    ),(
        'history.hold.retention_age_canceled_2',
        oils_i18n_gettext('history.hold.retention_age_canceled_2', 'Historical Hold Retention Age - Canceled (Hold Shelf expiration)', 'cgf', 'label'),
        FALSE
    ),(
        'history.hold.retention_age_canceled_3',
        oils_i18n_gettext('history.hold.retention_age_canceled_3', 'Historical Hold Retention Age - Canceled (Patron via phone)', 'cgf', 'label'),
        TRUE
    ),(
        'history.hold.retention_age_canceled_4',
        oils_i18n_gettext('history.hold.retention_age_canceled_4', 'Historical Hold Retention Age - Canceled (Patron in person)', 'cgf', 'label'),
        TRUE
    ),(
        'history.hold.retention_age_canceled_5',
        oils_i18n_gettext('history.hold.retention_age_canceled_5', 'Historical Hold Retention Age - Canceled (Staff forced)', 'cgf', 'label'),
        TRUE
    ),(
        'history.hold.retention_age_canceled_6',
        oils_i18n_gettext('history.hold.retention_age_canceled_6', 'Historical Hold Retention Age - Canceled (Patron via OPAC)', 'cgf', 'label'),
        FALSE
    );

CREATE OR REPLACE FUNCTION action.purge_holds() RETURNS INT AS $func$
DECLARE
  current_hold RECORD;
  purged_holds INT;
  cgf_d INTERVAL;
  cgf_f INTERVAL;
  cgf_c INTERVAL;
  prev_usr INT;
  user_start TIMESTAMPTZ;
  user_age INTERVAL;
  user_count INT;
BEGIN
  purged_holds := 0;
  SELECT INTO cgf_d value::INTERVAL FROM config.global_flag WHERE name = 'history.hold.retention_age' AND enabled;
  SELECT INTO cgf_f value::INTERVAL FROM config.global_flag WHERE name = 'history.hold.retention_age_fulfilled' AND enabled;
  SELECT INTO cgf_c value::INTERVAL FROM config.global_flag WHERE name = 'history.hold.retention_age_canceled' AND enabled;
  FOR current_hold IN
    SELECT
      rank() OVER (PARTITION BY usr ORDER BY COALESCE(fulfillment_time, cancel_time) DESC),
      cgf_cs.value::INTERVAL as cgf_cs,
      ahr.*
    FROM
      action.hold_request ahr
      LEFT JOIN config.global_flag cgf_cs ON (ahr.cancel_cause IS NOT NULL AND cgf_cs.name = 'history.hold.retention_age_canceled_' || ahr.cancel_cause AND cgf_cs.enabled)
    WHERE
      (fulfillment_time IS NOT NULL OR cancel_time IS NOT NULL)
  LOOP
    IF prev_usr IS NULL OR prev_usr != current_hold.usr THEN
      prev_usr := current_hold.usr;
      SELECT INTO user_start oils_json_to_text(value)::TIMESTAMPTZ FROM actor.usr_setting WHERE usr = prev_usr AND name = 'history.hold.retention_start';
      SELECT INTO user_age oils_json_to_text(value)::INTERVAL FROM actor.usr_setting WHERE usr = prev_usr AND name = 'history.hold.retention_age';
      SELECT INTO user_count oils_json_to_text(value)::INT FROM actor.usr_setting WHERE usr = prev_usr AND name = 'history.hold.retention_count';
      IF user_start IS NOT NULL THEN
        user_age := LEAST(user_age, AGE(NOW(), user_start));
      END IF;
      IF user_count IS NULL THEN
        user_count := 1000; -- Assumption based on the user visible holds routine
      END IF;
    END IF;
    -- Library keep age trumps user keep anything, for purposes of being able to hold on to things when staff canceled and such.
    IF current_hold.fulfillment_time IS NOT NULL AND current_hold.fulfillment_time > NOW() - COALESCE(cgf_f, cgf_d) THEN
      CONTINUE;
    END IF;
    IF current_hold.cancel_time IS NOT NULL AND current_hold.cancel_time > NOW() - COALESCE(current_hold.cgf_cs, cgf_c, cgf_d) THEN
      CONTINUE;
    END IF;

    -- User keep age needs combining with count. If too old AND within the count, keep!
    IF user_start IS NOT NULL AND COALESCE(current_hold.fulfillment_time, current_hold.cancel_time) > NOW() - user_age AND current_hold.rank <= user_count THEN
      CONTINUE;
    END IF;

    -- All checks should have passed, delete!
    DELETE FROM action.hold_request WHERE id = current_hold.id;
    purged_holds := purged_holds + 1;
  END LOOP;
  RETURN purged_holds;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.usr_visible_holds (usr_id INT) RETURNS SETOF action.hold_request AS $func$
DECLARE
    h               action.hold_request%ROWTYPE;
    view_age        INTERVAL;
    view_count      INT;
    usr_view_count  actor.usr_setting%ROWTYPE;
    usr_view_age    actor.usr_setting%ROWTYPE;
    usr_view_start  actor.usr_setting%ROWTYPE;
BEGIN
    SELECT * INTO usr_view_count FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_count';
    SELECT * INTO usr_view_age FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_age';
    SELECT * INTO usr_view_start FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_start';

    FOR h IN
        SELECT  *
          FROM  action.hold_request
          WHERE usr = usr_id
                AND fulfillment_time IS NULL
                AND cancel_time IS NULL
          ORDER BY request_time DESC
    LOOP
        RETURN NEXT h;
    END LOOP;

    IF usr_view_start.value IS NULL THEN
        RETURN;
    END IF;

    IF usr_view_age.value IS NOT NULL THEN
        -- User opted in and supplied a retention age
        IF oils_json_to_text(usr_view_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ) THEN
            view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
        ELSE
            view_age := oils_json_to_text(usr_view_age.value)::INTERVAL;
        END IF;
    ELSE
        -- User opted in
        view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
    END IF;

    IF usr_view_count.value IS NOT NULL THEN
        view_count := oils_json_to_text(usr_view_count.value)::INT;
    ELSE
        view_count := 1000;
    END IF;

    -- show some fulfilled/canceled holds
    FOR h IN
        SELECT  *
          FROM  action.hold_request
          WHERE usr = usr_id
                AND ( fulfillment_time IS NOT NULL OR cancel_time IS NOT NULL )
                AND COALESCE(fulfillment_time, cancel_time) > NOW() - view_age
          ORDER BY COALESCE(fulfillment_time, cancel_time) DESC
          LIMIT view_count
    LOOP
        RETURN NEXT h;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TABLE action.aged_hold_request (
    usr_post_code		TEXT,
    usr_home_ou		INT	NOT NULL,
    usr_profile		INT	NOT NULL,
    usr_birth_year		INT,
    staff_placed        BOOLEAN NOT NULL,
    LIKE action.hold_request
);
ALTER TABLE action.aged_hold_request
      ADD PRIMARY KEY (id),
      DROP COLUMN usr,
      DROP COLUMN requestor,
      DROP COLUMN sms_carrier,
      ALTER COLUMN phone_notify TYPE BOOLEAN
            USING CASE WHEN phone_notify IS NULL OR phone_notify = '' THEN FALSE ELSE TRUE END,
      ALTER COLUMN sms_notify TYPE BOOLEAN
            USING CASE WHEN sms_notify IS NULL OR sms_notify = '' THEN FALSE ELSE TRUE END,
      ALTER COLUMN phone_notify SET NOT NULL,
      ALTER COLUMN sms_notify SET NOT NULL;
CREATE INDEX aged_hold_request_target_idx ON action.aged_hold_request (target);
CREATE INDEX aged_hold_request_pickup_lib_idx ON action.aged_hold_request (pickup_lib);
CREATE INDEX aged_hold_request_current_copy_idx ON action.aged_hold_request (current_copy);
CREATE INDEX aged_hold_request_fulfillment_staff_idx ON action.aged_hold_request ( fulfillment_staff );

CREATE OR REPLACE VIEW action.all_hold_request AS
    SELECT DISTINCT
           COALESCE(a.post_code, b.post_code) AS usr_post_code,
           p.home_ou AS usr_home_ou,
           p.profile AS usr_profile,
           EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
           CAST(ahr.requestor <> ahr.usr AS BOOLEAN) AS staff_placed,
           ahr.id,
           ahr.request_time,
           ahr.capture_time,
           ahr.fulfillment_time,
           ahr.checkin_time,
           ahr.return_time,
           ahr.prev_check_time,
           ahr.expire_time,
           ahr.cancel_time,
           ahr.cancel_cause,
           ahr.cancel_note,
           ahr.target,
           ahr.current_copy,
           ahr.fulfillment_staff,
           ahr.fulfillment_lib,
           ahr.request_lib,
           ahr.selection_ou,
           ahr.selection_depth,
           ahr.pickup_lib,
           ahr.hold_type,
           ahr.holdable_formats,
           CASE
           WHEN ahr.phone_notify IS NULL THEN FALSE
           WHEN ahr.phone_notify = '' THEN FALSE
           ELSE TRUE
           END AS phone_notify,
           ahr.email_notify,
           CASE
           WHEN ahr.sms_notify IS NULL THEN FALSE
           WHEN ahr.sms_notify = '' THEN FALSE
           ELSE TRUE
           END AS sms_notify,
           ahr.frozen,
           ahr.thaw_date,
           ahr.shelf_time,
           ahr.cut_in_line,
           ahr.mint_condition,
           ahr.shelf_expire_time,
           ahr.current_shelf_lib
    FROM action.hold_request ahr
         JOIN actor.usr p ON (ahr.usr = p.id)
         LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
         LEFT JOIN actor.usr_address b ON (p.billing_address = b.id)
    UNION ALL
    SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib
    FROM action.aged_hold_request;

CREATE OR REPLACE FUNCTION action.age_hold_on_delete () RETURNS TRIGGER AS $$
DECLARE
BEGIN
    -- Archive a copy of the old row to action.aged_hold_request

    INSERT INTO action.aged_hold_request
           (usr_post_code,
            usr_home_ou,
            usr_profile,
            usr_birth_year,
            staff_placed,
            id,
            request_time,
            capture_time,
            fulfillment_time,
            checkin_time,
            return_time,
            prev_check_time,
            expire_time,
            cancel_time,
            cancel_cause,
            cancel_note,
            target,
            current_copy,
            fulfillment_staff,
            fulfillment_lib,
            request_lib,
            selection_ou,
            selection_depth,
            pickup_lib,
            hold_type,
            holdable_formats,
            phone_notify,
            email_notify,
            sms_notify,
            frozen,
            thaw_date,
            shelf_time,
            cut_in_line,
            mint_condition,
            shelf_expire_time,
            current_shelf_lib)
      SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib
        FROM action.all_hold_request WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER action_hold_request_aging_tgr
	BEFORE DELETE ON action.hold_request
	FOR EACH ROW
	EXECUTE PROCEDURE action.age_hold_on_delete ();

COMMIT;

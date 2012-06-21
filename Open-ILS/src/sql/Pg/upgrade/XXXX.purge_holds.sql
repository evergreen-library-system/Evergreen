
-- New global flags for the purge function
INSERT INTO config.global_flag  (name, enabled, label)
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
      LEFT JOIN config.global_flag cgf_cs ON (ahr.cancel_cause IS NOT NULL AND cgf_cs.name = 'history.hold.retenetion_age_canceled_' || ahr.cancel_cause AND cgf_cs.enabled)
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

BEGIN;

SELECT evergreen.upgrade_deps_block_check('1509', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.do_not_retain_year_of_birth_on_aged', 'circ',
    oils_i18n_gettext('circ.do_not_retain_year_of_birth_on_aged',
        'When aging circulations do not retain the year from patron date of birth',
        'cust', 'label'),
    oils_i18n_gettext('circ.do_not_retain_year_of_birth_on_aged',
        'When aging circulations do not retain the year from patron date of birth',
        'cust', 'description'),
    'bool', NULL);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.do_not_retain_post_code_on_aged', 'circ',
    oils_i18n_gettext('circ.do_not_retain_post_code_on_aged',
        'When aging circulations do not retain the patron postal code',
        'cust', 'label'),
    oils_i18n_gettext('circ.do_not_retain_post_code_on_aged',
        'When aging circulations do not retain the patron postal code',
        'cust', 'description'),
    'bool', NULL);


INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'holds.do_not_retain_year_of_birth_on_aged', 'circ',
    oils_i18n_gettext('holds.do_not_retain_year_of_birth_on_aged',
        'When aging holds do not retain the year from patron date of birth',
        'cust', 'label'),
    oils_i18n_gettext('holds.do_not_retain_year_of_birth_on_aged',
        'When aging holds do not retain the year from patron date of birth',
        'cust', 'description'),
    'bool', NULL);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'holds.do_not_retain_post_code_on_aged', 'circ',
    oils_i18n_gettext('holds.do_not_retain_post_code_on_aged',
        'When aging holds do not retain the patron postal code',
        'cust', 'label'),
    oils_i18n_gettext('holds.do_not_retain_post_code_on_aged',
        'When aging holds do not retain the patron postal code',
        'cust', 'description'),
    'bool', NULL);


CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
patron_ou               INTEGER;
kept_year               INTEGER;
kept_postcode           TEXT;
donot_keep_year         BOOLEAN;
donot_keep_postcode     BOOLEAN;
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found  
    FROM action.circulation   
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
    END IF;

    SELECT usr_home_ou FROM action.all_circulation WHERE id = OLD.id INTO patron_ou;

    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'circ.do_not_retain_year_of_birth_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_year;
    IF donot_keep_year IS NULL THEN donot_keep_year = FALSE; END IF; 
        
    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'circ.do_not_retain_post_code_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_postcode;
    IF donot_keep_postcode IS NULL THEN donot_keep_postcode = FALSE; END IF;
        
    IF donot_keep_year = TRUE THEN kept_year = NULL; ELSE kept_year = (SELECT usr_birth_year FROM action.all_circulation WHERE id = OLD.id); END IF;
    IF donot_keep_postcode = TRUE THEN kept_postcode = NULL; ELSE kept_postcode = (SELECT usr_post_code FROM action.all_circulation WHERE id = OLD.id); END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id, kept_postcode, usr_home_ou, usr_profile, kept_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables

    SELECT 'Y' INTO found FROM config.global_flag
        WHERE name = 'history.money.age_with_circs' AND enabled;

    IF found = 'Y' THEN
        PERFORM money.age_billings_and_payments_for_xact(OLD.id);
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.age_hold_on_delete () RETURNS TRIGGER AS $$
DECLARE
patron_ou               INTEGER;
kept_year               INTEGER;
kept_postcode           TEXT;
donot_keep_year         BOOLEAN;
donot_keep_postcode     BOOLEAN;
BEGIN
    -- Archive a copy of the old row to action.aged_hold_request
    SELECT usr_home_ou FROM action.all_hold_request WHERE id = OLD.id INTO patron_ou;

    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'holds.do_not_retain_year_of_birth_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_year;
    IF donot_keep_year IS NULL THEN donot_keep_year = FALSE; END IF;

    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'holds.do_not_retain_post_code_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_postcode;
    IF donot_keep_postcode IS NULL THEN donot_keep_postcode = FALSE; END IF;

    IF donot_keep_year = TRUE THEN kept_year = NULL; ELSE kept_year = (SELECT usr_birth_year FROM action.all_hold_request WHERE id = OLD.id); END IF;
    IF donot_keep_postcode = TRUE THEN kept_postcode = NULL; ELSE kept_postcode = (SELECT usr_post_code FROM action.all_hold_request WHERE id = OLD.id); END IF;

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
            current_shelf_lib,
            behind_desk)
            SELECT
                 kept_postcode,
                 usr_home_ou,
                 usr_profile,
                 kept_year,
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
                 current_shelf_lib,
                 behind_desk
              FROM action.all_hold_request WHERE id = OLD.id;

          RETURN OLD;
      END;
      $$ LANGUAGE 'plpgsql';


COMMIT;


